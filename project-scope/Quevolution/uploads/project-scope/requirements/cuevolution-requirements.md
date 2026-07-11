# Cuevolution — Functional & Non-Functional Requirements (MVP)

## Part A: Functional Requirements

### A1. Player Registration & Profile

| ID | Requirement |
|----|-------------|
| FR-1.1 | The system shall allow a visitor to register as a player by providing: full name, date of birth (or age), gender, email, mobile number, profile picture, location/town, and region. |
| FR-1.2 | The system shall reject registration if the calculated age is under 18. |
| FR-1.3 | The system shall require a username at registration and enforce uniqueness across all players. |
| FR-1.4 | The system shall require the player to select exactly one region from the 8 defined regions at registration. |
| FR-1.5 | The system shall allow the player to select a preferred venue from a preloaded list specific to their region, or select "Other" and manually specify a venue name. |
| FR-1.6 | The system shall require the player to select a notification preference of Email, SMS, or both, at registration. |
| FR-1.7 | The system shall allow the player to update their notification preference after registration. |
| FR-1.8 | The system shall allow a player to change their selected region only if they have not yet been recorded in a match; once a match record exists for the player, region shall be locked. |
| FR-1.9 | The system shall send a registration confirmation notification via the player's selected channel(s) upon successful registration. |
| FR-1.10 | The system shall enforce that a player can belong to at most one team at any time. |

### A2. Team Registration & Management

| ID | Requirement |
|----|-------------|
| FR-2.1 | The system shall allow a registered player to create a team, becoming its Team Captain. |
| FR-2.2 | The system shall allow the Team Captain to add other registered players directly to the team roster. |
| FR-2.3 | The system shall prevent a player from being added to a team if they are already a member of another team. |
| FR-2.4 | The system shall enforce a team roster size of minimum 5 and maximum 8 players. |
| FR-2.5 | The system shall mark a team as ineligible for draws if its roster falls below 5 players. |
| FR-2.6 | The system shall require a team to be associated with exactly one region. |

### A3. Venue Management (Admin)

| ID | Requirement |
|----|-------------|
| FR-3.1 | The system shall allow the admin to create, edit, and remove venues per region. |
| FR-3.2 | The system shall present region-specific venues as selectable options during player registration. |
| FR-3.3 | The system shall store custom ("Other") venue entries submitted by players for admin visibility. |

### A4. Qualification Pipeline & Stages

| ID | Requirement |
|----|-------------|
| FR-4.1 | The system shall model four sequential stages: Grassroots, Regional, Circuit, Finals. |
| FR-4.2 | The system shall support open (uncapped) participation at Grassroots and Regional stages. |
| FR-4.3 | The system shall support group/cluster stage groupings at the Grassroots stage, with no knockout bracket at this stage. |
| FR-4.4 | The system shall support group/cluster stage groupings at the Regional stage, followed by a knockout bracket limited to the top 8 players/teams per group. |
| FR-4.5 | The system shall support configurable capacity limits for Circuit stage entry (default: 128 men, 64 women, 20 teams). |
| FR-4.6 | The system shall support configurable capacity limits for Finals stage entry (default: 64 men, 32 women, 8 teams). |
| FR-4.7 | The system shall allow the admin to advance qualifying players/teams from one stage to the next. |
| FR-4.8 | The system shall track and display each player's/team's current stage. |

### A5. Draws

| ID | Requirement |
|----|-------------|
| FR-5.1 | The system shall allow the admin to enter or upload fixture pairings (player/team vs opponent, venue, date, time) for a given round. |
| FR-5.2 | The system shall trigger a notification to both participants of a fixture upon draw entry, containing opponent, venue, date, and time. |
| FR-5.3 | The system shall allow the admin to edit a draw entry prior to the match being played, triggering an update notification. |

### A6. Match Results & Points

| ID | Requirement |
|----|-------------|
| FR-6.1 | The system shall allow the admin to enter the result (winner/loser, or score if applicable) of a match. |
| FR-6.2 | The system shall use entered results to determine group standings and progression to Regional at the Grassroots stage (no knockout at this stage). |
| FR-6.3 | The system shall use entered results to determine group standings at the Regional stage, identify the top 8 players/teams per group, and determine knockout progression to Circuit from that point. |
| FR-6.4 | The system shall allow the admin to manually enter Cuevo Points for a player/team following a Circuit-stage (or later) match. |
| FR-6.5 | The system shall maintain a running total of Cuevo Points per player/team across the Circuit stage. |

### A7. Standings

| ID | Requirement |
|----|-------------|
| FR-7.1 | The system shall display public standings ranked by Cuevo Points for Individual Male, Individual Female, and Team categories. |
| FR-7.2 | Standings shall be viewable by any registered player without admin privileges. |
| FR-7.3 | The system shall update standings whenever new points are entered by the admin. |

### A8. Notifications

| ID | Requirement |
|----|-------------|
| FR-8.1 | The system shall send notifications via Email, SMS, or both, based on the player's selected preference. |
| FR-8.2 | The system shall implement SMS sending through an adapter/interface layer, decoupled from any specific SMS provider. |
| FR-8.3 | The system shall send a notification for: (a) registration confirmation, (b) draw/fixture assignment. |
| FR-8.4 | The system shall log the delivery status of each notification attempt for admin troubleshooting. |

### A9. Admin

| ID | Requirement |
|----|-------------|
| FR-9.1 | The system shall provide a single admin role with access to manage regions, venues, players, teams, draws, results, and points. |
| FR-9.2 | The system shall require admin authentication distinct from player accounts. |
| FR-9.3 | The system shall allow the admin to view all registered players and teams filtered by region, category, and stage. |

---

## Part B: Non-Functional Requirements

### B1. Performance
| ID | Requirement |
|----|-------------|
| NFR-1.1 | The system shall support concurrent registration bursts (e.g., regional registration windows opening) without perceptible degradation, targeting page response times under 2 seconds for standard pages under normal load. |
| NFR-1.2 | Standings pages shall reflect newly entered points within a reasonable refresh window suitable for LiveView's real-time update model. |

### B2. Scalability
| ID | Requirement |
|----|-------------|
| NFR-2.1 | The system shall be designed to accommodate growth from 8 regions to additional regions in future phases without structural redesign. |
| NFR-2.2 | Stage capacity limits (Circuit/Finals) shall be stored as configurable values rather than hardcoded constants. |
| NFR-2.3 | The data model shall accommodate future stages, categories, or competition formats without breaking existing records. |

### B3. Availability & Reliability
| ID | Requirement |
|----|-------------|
| NFR-3.1 | The system shall target high availability during active tournament periods (draws, results entry), minimizing downtime windows to off-peak hours. |
| NFR-3.2 | Notification sending shall be retried on transient failure (e.g., SMS provider timeout) with failure logging, rather than silently dropping. |
| NFR-3.3 | The system shall use PostgreSQL with appropriate backups/point-in-time recovery to prevent data loss of registration, results, and points data. |

### B4. Security
| ID | Requirement |
|----|-------------|
| NFR-4.1 | Player and admin authentication credentials shall be stored using industry-standard hashing (e.g., bcrypt/argon2), never in plaintext. |
| NFR-4.2 | Admin functionality shall be protected by role-based access control, inaccessible to standard player accounts. |
| NFR-4.3 | All data in transit shall be encrypted via HTTPS/TLS. |
| NFR-4.4 | Personally identifiable information (name, email, mobile number, DOB) shall be protected against unauthorized access and export. |
| NFR-4.5 | The system shall validate and sanitize all user input to prevent injection attacks (SQL injection, XSS), consistent with Phoenix/Ecto best practices. |

### B5. Data Privacy & Compliance
| ID | Requirement |
|----|-------------|
| NFR-5.1 | The system shall handle player personal data in accordance with the Kenya Data Protection Act, 2019, including lawful basis for processing and data minimization. |
| NFR-5.2 | The system shall allow the admin to remove or anonymize a player's personal data upon a valid deletion request, where feasible without breaking historical match/points records. |
| NFR-5.3 | Mobile numbers and email addresses shall only be used for the notification purposes explicitly consented to at registration. |

### B6. Usability
| ID | Requirement |
|----|-------------|
| NFR-6.1 | The registration flow shall be completable on a standard mobile browser, given the likely mobile-first usage pattern in Kenya. |
| NFR-6.2 | Form validation errors (e.g., age restriction, duplicate username) shall be communicated clearly and immediately, leveraging LiveView's real-time validation. |
| NFR-6.3 | The admin interface for draw entry and results/points entry shall minimize manual steps, given draws and points are entered per-match/per-round in volume. |

### B7. Maintainability & Extensibility
| ID | Requirement |
|----|-------------|
| NFR-7.1 | The SMS notification integration shall be implemented as a swappable adapter (behaviour/interface) to allow provider changes (e.g., Africa's Talking or others) without core system changes. |
| NFR-7.2 | The codebase shall follow Phoenix/Elixir context boundaries (e.g., Accounts, Teams, Venues, Competitions, Notifications) to keep domains decoupled for future feature growth. |
| NFR-7.3 | Business rules subject to change (stage capacities, points values) shall be stored as data/configuration, not hardcoded in application logic. |

### B8. Compatibility
| ID | Requirement |
|----|-------------|
| NFR-8.1 | The web application shall be responsive and function correctly on modern desktop and mobile browsers (Chrome, Safari, Firefox, Edge — current and prior major versions). |
| NFR-8.2 | The application shall function on low-to-mid bandwidth conditions typical of parts of the target regions. |

### B9. Observability
| ID | Requirement |
|----|-------------|
| NFR-9.1 | The system shall log key admin actions (draw entry, results entry, points entry) for audit purposes. |
| NFR-9.2 | The system shall provide basic application health/error monitoring suitable for identifying notification delivery failures or system errors during live tournament activity. |

---

## Notes on Traceability

Each functional requirement (FR-x.x) maps to a corresponding section in the Scope Document (Section 5). Non-functional requirements apply system-wide rather than to a single module. Any requirement changes should be version-controlled alongside the scope document to keep both in sync as the MVP evolves.
