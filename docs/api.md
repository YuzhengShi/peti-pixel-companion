# API reference

All routes live in `api/src/routes/` and are registered in [`api/src/index.ts`](../api/src/index.ts). Successful responses are JSON in the form `{ "data": ... }`. Errors are `{ "error": { "code": "...", "message": "..." } }`.

Authentication is a JWT in an HttpOnly cookie named `token`, checked by `requireAuth`. Admin routes also pass through `requireRole`.

## Utility

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/ping` | No | Health check. Returns `{ "data": { "message": "pong" } }`. |

## Authentication

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/register` | No | Create a user with the default role and set the token cookie. |
| POST | `/api/auth/login` | No | Verify credentials and return the user, including the role. |
| POST | `/api/auth/logout` | Yes | Clear the token cookie. |
| GET | `/api/auth/me` | Yes | Return the current user, including the role. |

## Memories

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/memories` | Yes | Paginated list. Supports `?search=` and `?category=`. |
| POST | `/api/memories` | Yes | Create a memory with server-side validation. |
| PUT | `/api/memories/:id` | Yes | Update one of your own memories. |
| DELETE | `/api/memories/:id` | Yes | Soft-delete one of your own memories. |

Memory categories are `observation`, `strategy`, `preference` and `milestone`. Importance runs from 1 to 5.

## Pets

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/pets` | Yes | Create a pet (one per user). |
| GET | `/api/pets/mine` | Yes | Get the current user's pet. |
| PUT | `/api/pets/:id` | Yes | Update your own pet. |

## Profiles

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/profiles` | Yes | Submit the scored result for one assessment domain. |
| GET | `/api/profiles` | Yes | Get all of your stored domain results. |
| POST | `/api/profiles/generate` | Yes | Generate the written profile with a Bedrock model. Returns 400 until all 6 domains are stored. |
| GET | `/api/profiles/content` | Yes | Get the generated profile text, its short summary and its update time (each is `null` if none exists yet). |

## Chat and messages

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/chat` | Yes | Send `{ "message": "..." }`. The response is a Server-Sent Events stream (see below). |
| GET | `/api/messages` | Yes | Paginated message history. |
| DELETE | `/api/messages/:id` | Yes | Delete one of your own messages. |

### Chat stream events

Each event is a line `data: <json>` with a `type` field.

| Type | Meaning |
|------|---------|
| `sentence` | One sentence of Peti's reply. Replies are split on sentence-ending punctuation so the client can show them one at a time. |
| `state` | A change in mood, energy or animation (and, when the relationship stage advances, a `spriteSheet` path). |
| `proactive` | A message Peti queued earlier with `pending_proactive_message`. It is delivered at the start of the next chat request. |
| `error` | The agent or its container failed. |
| `done` | The reply is finished. Sent after 2 seconds without new output, or after a 120 second hard timeout. |

## Admin

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/admin/users` | Admin | List users with search and pagination. |
| GET | `/api/admin/users/:id` | Admin | User detail with pet, profile and counts. |
| PUT | `/api/admin/users/:id` | Admin | Update a user's role. |
| DELETE | `/api/admin/users/:id` | Admin | Delete a user and, by cascade, their data. |

## External API

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/weather` | Yes | OpenWeatherMap proxy. Use `?lat=&lon=` or `?city=`. Needs `OPENWEATHERMAP_API_KEY`. |

## Internal routes (agent containers only)

These routes are called by the MCP tools inside the agent containers, not by the browser. They are mounted at `/api/internal` and require the `x-internal-secret` header to match `INTERNAL_SECRET` (`requireInternal`).

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/internal/pet-state` | Update mood, energy, animation or the pending proactive message, and push a `state` event to an open chat stream. |
| POST | `/api/internal/memory` | Create a memory. A `milestone` with importance 4 or more raises the pet's level by one. |
| GET | `/api/internal/memory` | Query a user's active memories, ordered by importance then recency (keyword match on `q`, up to 20 results). |
| POST | `/api/internal/profile` | Update the stored profile text, and advance the pet's level when `relationship_stage` moves up. |

Set `INTERNAL_SECRET` to a long random value in any deployment. The built-in default is for local development only.
