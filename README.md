<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/499e7a45-43b7-4946-a97a-f8a5cef16b66" />

# WhaleTracker

WhaleTracker is a stats tracking system for the Kogasatopia TF2 server. It has three parts:

- a SourceMod plugin (WhaleTracker) that runs on the server to record in-game events
- Stat records are deferred from Sourcemod to a Rust app called WhaleTracker-Rust, this allows for SQL writes with multithreading rather than keeping the work on TF2's single thread
- Frontend found in the Kogasatopia-Frontend-Elixir repo that contains a cumulative stats page, a maps database, match logs inspired by supstats2 and a live chat connection

WhaleTracker is meant to be comprehensive, such as ranking clients through an algorithm and tracking things like backstabs and market gardens. This gives players more of a reason to play, reason to improve, and the ability to pay attention to their performance. Inspired by HLstatsX idea.

[Visit WhaleTracker's frontend here.](https://kogasa.tf/stats)
