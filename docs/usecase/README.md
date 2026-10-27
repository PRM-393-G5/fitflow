# Use case diagrams

`docs/usecase.drawio` holds seven pages (tabs). Open it in
[draw.io](https://app.diagrams.net) or the draw.io desktop app. The PNGs here
are renders of each page for reading on GitHub:

| Page | Actors | What it covers |
|---|---|---|
| [Overview](1-overview.png) | User, Admin; Google Sign-In, Camera + ML Kit, OpenAI, Device OS | The two front ends and their main use cases |
| [Account & data](2-account-data.png) | User, Google Sign-In | Required sign-in, sync, sign-out, account deletion, JSON backup |
| [Workout planning](3-workout-planning.png) | User, OpenAI | Onboarding, library, custom and AI-generated plans, weekly schedule |
| [Training & form check](4-training-form-check.png) | User, Camera + ML Kit, OpenAI | Guided workouts, camera counting, hands-free mode, AI form check |
| [Nutrition & body metrics](5-nutrition-body-metrics.png) | User, OpenAI | Targets, AI meal plans, three ways to log a meal, weight log |
| [Progress & settings](6-progress-settings.png) | User, Device OS | Dashboard, muscle map, achievements, sessions, reminders, theme |
| [Admin web](7-admin-web.png) | Admin | Dashboard, AI usage, user management, workout templates |

Relationships use UML notation: «include» (the base always uses it),
«extend» with its condition in brackets (optional behaviour), and
generalization (hollow triangle) for kinds of a use case.

`docs/usecase.puml` has the same model as PlantUML (automatic layout).
Both files are generated from `generate.py`: edit the model there and run
`python3 docs/usecase/generate.py docs/usecase.drawio docs/usecase.puml`.
