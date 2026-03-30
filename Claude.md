# Project Structure

## Directory Structure

### Research Repos
- marketplace-backend
  - This is the main backend repository for all marketplace services. All new API's should be written in this repo
  - Contains the backend services for all marketplace
  - Read the Claude.md file in this directory for more information
- marketplace-graphql. All new GraphQL queries and mutations should be written in this repo
  - Contains the GraphQL services for all marketplace
  - Read the Claude.md file in this directory for more information
- Legacy
  - A directory containing legacy code that is no longer updated
  - The code in this directory should be referenced when planning new projects
  - The code in this directory should not be used for new development
  - The code in this directory will be re-implemented
    - When re-implementing, frontend projects will call marketplace-graphql queries and mutations
    - marketplace-graphql calls API's in marketplace-backend, along with Legacy API's
      - The Legacy API's are in the Legacy directory

### Shaping Projects
This directory contains projects that are being planned or are in progress
When in planning mode for projects, write all planning documents in this directory

Each project should contain the following files:
- Features.md
  - Required features to complete the project
- Services.md
  - Services that will be created or updated
- project.json
  - Configuration file with `repositories` (array of {org, repo} objects) and `notion_docs` (array of Notion URLs)
- planning-state.md
  - Living document tracking what has been identified, what still needs research, and unanswered questions
  - Updated each time a "shape" session runs

## Shape Command

When the user says **"shape N"** (e.g., "shape 4"), follow this procedure:

1. **Resolve the project**: Find the directory under `Shaping Projects/` whose name starts with the zero-padded number (e.g., `004`).

2. **Read project state**: Read `project.json`, `Features.md`, `Services.md`, and `planning-state.md` from that project directory.

3. **Gather context from Notion**: For each URL in `notion_docs`, use the Notion MCP server (`mcp-notion` / `notion-fetch`) to retrieve the document content.

4. **Sync local repos to origin/main**: Before researching, ensure each local repo is up to date. For each repo in `repositories` that exists locally under `/Users/cpies/code/AI-Agents/Research Repos/`:
   - `cd` into the repo directory
   - Run `git status` to check for uncommitted changes or non-main branch
   - Run `git pull origin main`
   - **If the pull fails or there are uncommitted changes**: STOP and notify the user. Report which repo has the issue, what branch it's on, and whether they need to stash changes, switch branches, or resolve conflicts. Do NOT proceed with research on that repo until the user confirms it's resolved.
   - **If the pull succeeds**: proceed with research on that repo.

5. **Research repositories**: For each entry in `repositories`, use the GitHub CLI (`gh`) to research the repo:
   - `gh repo view {org}/{repo}` for repo overview
   - Search for relevant code, issues, PRs, and discussions related to the project's scope
   - Read relevant source files from the local Research Repos directory at `/Users/cpies/code/AI-Agents/Research Repos/`

6. **Enter planning mode**: Analyze all gathered context and work with the user to:
   - Identify features, services, APIs, data models, and migration steps
   - Update `Features.md` and `Services.md` with findings
   - Flag unanswered questions and areas needing more research

7. **Update planning-state.md**: After each session, update `planning-state.md` with:
   - **Identified So Far**: What has been discovered and documented
   - **Still Needs Research**: Areas that require further investigation
   - **Unanswered Questions**: Open questions that need answers from team members or further exploration
   - **Research Sources Consulted**: Which repos, docs, and files were reviewed

## Update Command

When the user says **"update N"** (e.g., "update 4"), follow this procedure:

The user is indicating that `project.json` for that project has been modified — repositories or Notion docs were added, removed, or changed. The goal is to re-sync `planning-state.md` with the updated references.

1. **Resolve the project**: Find the directory under `Shaping Projects/` whose name starts with the zero-padded number (e.g., `004`).

2. **Read current state**: Read `project.json` and `planning-state.md`.

3. **Diff the references**: Compare the current `project.json` references against the "Research Sources Consulted" section of `planning-state.md` to identify what was added, removed, or changed.

4. **Sync new/changed repos to origin/main**: For any new or changed repositories that exist locally under `/Users/cpies/code/AI-Agents/Research Repos/`, run the same sync procedure as the Shape Command (step 4) — check `git status`, run `git pull origin main`, and stop to notify the user if there are issues.

5. **Fetch new/changed references**:
   - For any **new or changed Notion docs**: fetch them via the Notion MCP server and summarize what they contain.
   - For any **new or changed repositories**: use `gh` CLI and/or local Research Repos to gather an overview of the repo and its relevance to the project.
   - For **removed references**: note them as removed so they are no longer treated as active sources.

6. **Update planning-state.md**:
   - Add new sources to "Research Sources Consulted" with a brief summary of what was found.
   - Move any newly discovered items into "Identified So Far" or "Still Needs Research" as appropriate.
   - Add any new open questions to "Unanswered Questions".
   - Note any removed references and clean up items that were solely based on those sources.
   - Add a dated changelog entry at the bottom noting what references changed (e.g., `2026-03-27: Added repo deseretdigital/marketplace-graphql, removed Notion doc X`).

7. **Report to user**: Summarize what changed and what new research items were identified from the updated references.
