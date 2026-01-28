-- Enable UUID extension for robust, unique IDs without centralized coordination
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. AUDIO CLIPS
-- Metadata plus reference to what could be an AWS S3 bucket
-- We do NOT store the raw audio bytes here to keep the DB fast.
CREATE TABLE audio_clips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sensor_id VARCHAR(50) NOT NULL,            -- Which sensor recorded this?
    file_path TEXT NOT NULL UNIQUE,            -- Reference to S3 bucket (or local path?)
    duration_seconds FLOAT NOT NULL CHECK (duration_seconds > 0),
    sample_rate_hz INTEGER NOT NULL,
    channels INTEGER NOT NULL DEFAULT 1,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), -- When the event happened
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()   -- When we inserted it
);

-- Index for temporal queries. This could be an important index since the time at which an event happened might be a major factor for querying
CREATE INDEX idx_audio_clips_recorded_at ON audio_clips(recorded_at);
-- Index for finding specific sensor data fast
CREATE INDEX idx_audio_clips_sensor_id ON audio_clips(sensor_id);


-- 2. LABEL DEFINITIONS
-- A lookup table. Ensures we don't have "Drone", "drone", and "DRONE" mixed up.
-- Could in the future have even more things about 
CREATE TABLE label_definitions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);


-- 3. AUDIO ANNOTATIONS (The "Time-Series" Labels)
-- Links a label to a specific TIME RANGE within a clip.
CREATE TABLE audio_annotations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    audio_clip_id UUID NOT NULL REFERENCES audio_clips(id) ON DELETE CASCADE,
    label_id INTEGER NOT NULL REFERENCES label_definitions(id),
    
    start_time FLOAT NOT NULL,
    end_time FLOAT NOT NULL,
    confidence FLOAT DEFAULT 1.0 CHECK (confidence >= 0 AND confidence <= 1.0),
    
    annotator_id VARCHAR(50), -- Maybe this could be an AI model or a human user id? Didnt create an annotator table yet though, felt like this would go beyond the scope of a technical assignment
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Validation: End time must be after start time
    CONSTRAINT check_time_validity CHECK (end_time > start_time)
);

-- Composite Index: Crucial for "Show me all labels for this specific clip"
CREATE INDEX idx_annotations_clip_lookup ON audio_annotations(audio_clip_id, start_time);


-- 4. COMPUTED FEATURES 
-- As you said in the task, computing features is expensive and computing them twice would be stupid. 
-- This is why we have this as a cache for all the features we have computed
CREATE TABLE computed_features (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    audio_clip_id UUID NOT NULL REFERENCES audio_clips(id) ON DELETE CASCADE,
    
    feature_type VARCHAR(50) NOT NULL, -- Spectrogram, MFCC, Chroma.........
    
    -- JSONB is the most flexible option. Im not just lazy because I dont specify the computation params here ;)
    computation_params JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- Feature data. Depends on how big. If too big, we put that in S3 and store reference.
    feature_data BYTEA NOT NULL,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- We do this so wen dont compute the same audio for the same feature with the same parameters
    UNIQUE (audio_clip_id, feature_type, computation_params)
);

-- Index to quickly check "DO we have this exact same feature already?" Because as we said, computing twice is dumb
CREATE INDEX idx_features_lookup ON computed_features(audio_clip_id, feature_type);