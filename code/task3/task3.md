Here is my routing idea, I would like to talk about it in person.

For Task 3, the main challenge is the massive 600ms transmission time. Collisions are basically fatal at that speed—wasting over a second per error—so my approach prioritizes avoiding them over raw speed.

**1. Routing**
I used a simple gradient system. The user device broadcasts a 'Hop 0' signal. Nearby sensors hear it and become 'Hop 1,' rebroadcasting that status. Further sensors become 'Hop 2,' and so on. When a sensor detects a drone, it doesn't need a full map; it just forwards the packet to any neighbor with a lower hop count. It's simple and requires very little memory.

**2. Handling Traffic**
With 50 sensors potentially spotting the same drone, if everyone transmits at once, the network jams. I used a randomized backoff strategy. If a sensor needs to send, it rolls a dice based on how many neighbors it has (1/x chance). If it 'loses,' it waits a bit and tries again. This small wait is much faster than fixing a collision. X should be a function of how many sensors there are as well as how dense, and how loud the average drone would be.

**3. Saving Energy**
Instead of sending a confirmation packet back (which costs another 600ms), I use the fact that radio is omnidirectional. If I send data to a neighbor, I just listen. If I hear them forwarding that same data to the next hop, I know they received it. It confirms delivery without wasting battery on an extra message.