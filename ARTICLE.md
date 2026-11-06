# A missed shot can still change the ground

In Star Arc Battle’s training range, a shell can miss its target and leave a crater. A scripted key sequence nudges the aim with E, then holds and releases Space. The shell arcs past the target and lands on the far slope.

Godot advances the projectile at 120 physics ticks per second. The collision code samples points along the distance covered in each tick. When the shell hits, the game changes nearby heights in the ground profile. The renderer draws that profile, and later shots check collisions against the same surface.

At the recorded impact point, the ground dropped by about 30 game units. I captured the run from the pinned public version 0.5.2 in Godot 4.6.2. The movie clock was fixed at 60 frames per second, giving about 9.4 seconds of raw footage.

Open `project.godot` in Godot 4.6 and run the main scene. Select 竞技场 (Arena), choose 靶场训练 (Training Range), then select 进入竞技场 (Enter Arena). Use Q or E to aim, then hold and release Space. Training displays the full predicted arc. I’d compare the predicted landing point with where the shell actually hits at several angles before relying on the preview for precise aim. The setup and reuse terms are in the source. [Pinned GitHub snapshot](https://github.com/Angelov1314/star-arc-battle/tree/dddeefb011bae735161013eda401a9c6d20573ee)
