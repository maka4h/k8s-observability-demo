import os
import logging
from typing import List, Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr
from sqlalchemy import create_engine, Column, Integer, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.sql import func
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi import Response
import nats
import asyncio
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Database setup
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://demo:demo123@localhost:5432/demo")
engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# NATS client
nc: Optional[nats.NATS] = None

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration', ['method', 'endpoint'])
USER_CREATED = Counter('users_created_total', 'Total users created')
USER_QUERY = Counter('users_queried_total', 'Total user queries')

# Models
class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

# Pydantic schemas
class UserCreate(BaseModel):
    name: str
    email: EmailStr

class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    created_at: datetime
    
    class Config:
        from_attributes = True

# Lifespan context manager for startup/shutdown
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global nc
    logger.info("Starting up user service...")
    
    # Create database tables
    Base.metadata.create_all(bind=engine)
    logger.info("Database tables created")
    
    # Connect to NATS
    try:
        nats_url = os.getenv("NATS_URL", "nats://localhost:4222")
        nc = await nats.connect(nats_url)
        logger.info(f"Connected to NATS at {nats_url}")
    except Exception as e:
        logger.error(f"Failed to connect to NATS: {e}")
        nc = None
    
    yield
    
    # Shutdown
    logger.info("Shutting down user service...")
    if nc:
        await nc.close()
        logger.info("NATS connection closed")

# Create FastAPI app
app = FastAPI(
    title="User Service",
    description="User management service with observability",
    version="1.0.0",
    lifespan=lifespan
)

# Dependency to get database session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Health check endpoint
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    health_status = {
        "status": "healthy",
        "service": "user-service",
        "database": "connected",
        "nats": "connected" if nc and nc.is_connected else "disconnected"
    }
    
    # Check database connection
    try:
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()
    except Exception as e:
        health_status["database"] = f"error: {str(e)}"
        health_status["status"] = "unhealthy"
        return JSONResponse(status_code=503, content=health_status)
    
    return health_status

# Metrics endpoint
@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

# User endpoints
@app.post("/api/users", response_model=UserResponse, status_code=201)
async def create_user(user: UserCreate, db: Session = Depends(get_db)):
    """Create a new user"""
    logger.info(f"Creating user: {user.email}")
    
    try:
        # Check if user already exists
        existing_user = db.query(User).filter(User.email == user.email).first()
        if existing_user:
            logger.warning(f"User already exists: {user.email}")
            raise HTTPException(status_code=400, detail="User with this email already exists")
        
        # Create user
        db_user = User(name=user.name, email=user.email)
        db.add(db_user)
        db.commit()
        db.refresh(db_user)
        
        # Publish event to NATS
        if nc and nc.is_connected:
            try:
                event = {
                    "event": "user.created",
                    "user_id": db_user.id,
                    "email": db_user.email,
                    "timestamp": datetime.utcnow().isoformat()
                }
                await nc.publish("user.created", str(event).encode())
                logger.info(f"Published user.created event for user {db_user.id}")
            except Exception as e:
                logger.error(f"Failed to publish NATS event: {e}")
        
        USER_CREATED.inc()
        REQUEST_COUNT.labels(method="POST", endpoint="/api/users", status=201).inc()
        logger.info(f"User created successfully: {db_user.id}")
        
        return db_user
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating user: {e}")
        db.rollback()
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/api/users", response_model=List[UserResponse])
async def list_users(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """List all users with pagination"""
    logger.info(f"Listing users (skip={skip}, limit={limit})")
    
    try:
        users = db.query(User).offset(skip).limit(limit).all()
        USER_QUERY.inc()
        REQUEST_COUNT.labels(method="GET", endpoint="/api/users", status=200).inc()
        logger.info(f"Retrieved {len(users)} users")
        return users
    except Exception as e:
        logger.error(f"Error listing users: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/api/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: Session = Depends(get_db)):
    """Get a specific user by ID"""
    logger.info(f"Fetching user: {user_id}")
    
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            logger.warning(f"User not found: {user_id}")
            raise HTTPException(status_code=404, detail="User not found")
        
        USER_QUERY.inc()
        REQUEST_COUNT.labels(method="GET", endpoint="/api/users/{id}", status=200).inc()
        logger.info(f"User retrieved: {user_id}")
        return user
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching user: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.delete("/api/users/{user_id}", status_code=204)
async def delete_user(user_id: int, db: Session = Depends(get_db)):
    """Delete a user"""
    logger.info(f"Deleting user: {user_id}")
    
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            logger.warning(f"User not found: {user_id}")
            raise HTTPException(status_code=404, detail="User not found")
        
        db.delete(user)
        db.commit()
        
        # Publish event to NATS
        if nc and nc.is_connected:
            try:
                event = {
                    "event": "user.deleted",
                    "user_id": user_id,
                    "timestamp": datetime.utcnow().isoformat()
                }
                await nc.publish("user.deleted", str(event).encode())
                logger.info(f"Published user.deleted event for user {user_id}")
            except Exception as e:
                logger.error(f"Failed to publish NATS event: {e}")
        
        REQUEST_COUNT.labels(method="DELETE", endpoint="/api/users/{id}", status=204).inc()
        logger.info(f"User deleted: {user_id}")
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting user: {e}")
        db.rollback()
        raise HTTPException(status_code=500, detail="Internal server error")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
