from databases import Database
from fastapi import FastAPI, HTTPException, Query, Security, Header, Depends
from pydantic import BaseModel
from datetime import datetime
from typing import List, Optional
import os

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:password@localhost:5433/omnisent")

# --- Security Stub (Task Requirement) ---
API_KEY_NAME = "X-API-Key"
async def get_api_key(api_key: str = Header(None)):
    if api_key != "omnisent-secure-key":
        print("Unauthorized access attempt.")
        print(f"Received API Key: {api_key}")
        
        # Allowing None for now to make testing easy, 
        # but in production, raise a 403 for lack of auth!
        # In production I would also go with Bearer Token or OAuth2
        pass 
    return api_key

database = Database(DATABASE_URL)
app = FastAPI(title="Omnisent Cloud API",dependencies=[Depends(get_api_key)])

class DetectionEventPayload(BaseModel):
    sensorId: str
    messageId: str
    position: dict  # {'lat': float, 'lng': float}
    classification: int
    prediction: int
    amplitude: float
    timestamp: datetime



@app.on_event("startup")
async def startup(): await database.connect()

@app.on_event("shutdown")
async def shutdown(): await database.disconnect()

# --- 1. Batch Upload (Ingest) ---
@app.post("/events/batch")
async def upload_batch(events: List[DetectionEventPayload]):
    if not events: return {"saved": 0}
    
    # Here we implement idempotency using ON CONFLICT DO NOTHING
    query = """
        INSERT INTO detection_events (message_id, sensor_id, latitude, longitude, classification, prediction, amplitude, timestamp)
        VALUES (:msg_id, :sid, :lat, :lng, :class_val, :pred, :amp, :ts)
        ON CONFLICT (message_id) DO NOTHING
    """
    values = [
        {
            "msg_id": e.messageId, 
            "sid": e.sensorId, 
            "lat": e.position['lat'], 
            "lng": e.position['lng'], 
            "class_val": e.classification, 
            "pred": e.prediction, 
            "amp": e.amplitude, 
            "ts": e.timestamp.replace(tzinfo=None) # Ensure naive UTC for Postgres
        } 
        for e in events
    ]
    await database.execute_many(query=query, values=values)
    return {"status": "ok", "processed": len(values)}

# --- 2. Latest State (Task Requirement: "latest per sensor") ---
@app.get("/sensors/latest")
async def get_latest_sensor_state(
    limit: int = 100, 
    offset: int = 0
):
    # DISTINCT ON is perfect here
    query = """
        SELECT DISTINCT ON (sensor_id) 
            message_id, sensor_id, latitude, longitude, classification, 
            prediction, amplitude, timestamp
        FROM detection_events
        ORDER BY sensor_id, timestamp DESC
        LIMIT :limit OFFSET :offset
    """
    rows = await database.fetch_all(query=query, values={"limit": limit, "offset": offset})
    return [
        {
            "sensorId": r["sensor_id"],
            "latestEvent": {
                "messageId": r["message_id"],
                "timestamp": r["timestamp"],
                "classification": r["classification"],
                "position": {"lat": r["latitude"], "lng": r["longitude"]}
            }
        } 
        for r in rows
    ]

# --- 3. History (Task Requirement: Time range + SensorID) ---
@app.get("/events")
async def get_history(
    start_iso: datetime, 
    end_iso: datetime, 
    sensor_id: Optional[str] = None
):
    # Base query. Important to only select whats needed for performance
    query = """
        SELECT message_id, sensor_id, latitude, longitude, classification, 
               prediction, amplitude, timestamp
        FROM detection_events
        WHERE timestamp >= :start AND timestamp < :end
    """
    
    # Dynamic filtering
    params = {"start": start_iso.replace(tzinfo=None), "end": end_iso.replace(tzinfo=None)}
    
    if sensor_id:
        query += " AND sensor_id = :sid"
        params["sid"] = sensor_id
        
    query += " ORDER BY timestamp ASC"
    
    rows = await database.fetch_all(query=query, values=params)
    
    return [
        {
            "sensorId": r["sensor_id"], 
            "messageId": r["message_id"], 
            "position": {"lat": r["latitude"], "lng": r["longitude"]}, 
            "classification": r["classification"], 
            "prediction": r["prediction"], 
            "amplitude": r["amplitude"], 
            "timestamp": r["timestamp"].isoformat()
        } 
        for r in rows
    ]