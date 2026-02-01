I assume we will talk about this more in the interview, so here just the major tradeoffs I considered:



JSONB format on computation params: CHose flexibility over speed and 
uuid on primary keys: chose making them work on distributed systems over speed, storage space and possible index fragmentation
audio annotations:  I chose flexible labelling over speed and avoiding join overheads, by making this a separate table (easy choice)
feature_data as bytea: Depends on size... I chose bytea for slower 


An important distinction that I have made in my eyes is separating detection events as a table from the actual audio data. I have
made this distinction for two reasons: 1. Uploading audio can take a long time, and untl then there would have to be a placeholder. Like this I can quickly send detection events and have that persisted on the backend. 2. Maybe sometimes in the future I want the audio files to be separate from the detection events. As in, maybe I want the audio files of some False Negatives, or of a dog barking sound for fine tuning. 
To have the best of both worlds, I did create a view to put the two together conveniently.



I added some more explanations as comments in the code. Anything else I am happy to discuss in the interview. 