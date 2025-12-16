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
