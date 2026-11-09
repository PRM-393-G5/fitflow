# Use case diagram

`docs/usecase.drawio` holds one page with FitFlow's main use cases only;
set-up and housekeeping (onboarding, settings, export, sync, account
deletion) are left out. Open it in [draw.io](https://app.diagrams.net) or
the draw.io desktop app.
[usecase.png](usecase.png) is a render of it for reading on GitHub.

All use cases sit in one system boundary, top to bottom:

| Rows | Actors | What they cover |
|---|---|---|
| Sign-in | Guest; Google Sign-In | Sign in (Google on mobile, email & password on the admin web) |
| Mobile app | User | Library, schedule, guided workouts, form check, nutrition, meal log, body weight, progress, history |
| Sign out | User, Admin | Signing out of either front end |
| Admin web | Admin | Dashboard, AI usage, user management, workout templates |

A Guest is someone not signed in: signing in is all they can do. User and
Admin are signed in, so every other use case belongs to them. That is how
the diagram shows sign-in is required, without an «include» from each use
case. *Authenticate* (italics: abstract) is the parent of the two ways to
sign in.

Relationships use UML notation: «include» (the base always uses it) and
generalization (hollow triangle) for kinds of a use case.

`docs/usecase.puml` has the same model as PlantUML (automatic layout).
Both files are generated from `generate.py`: edit the model there and run
`python3 docs/usecase/generate.py docs/usecase.drawio docs/usecase.puml`.
Then refresh the PNG: open `docs/usecase.drawio` in draw.io and
File → Export as → PNG (border 10, transparent background off), saving it
as `docs/usecase/usecase.png`.
