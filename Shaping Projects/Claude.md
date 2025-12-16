# Research Guidelines for Shaping Projects

## Research Repositories Location

When researching legacy code or existing implementations for shaping projects, look in the **Research Repos** folder located at:

```
/Users/cpies/code/AI-Agents/Research Repos/
```

### Key Directories

- **Legacy/**: Contains legacy codebases and historical implementations
- **ddm-platform/**: DDM platform code
- **ddm-protobuf/**: Protocol buffer definitions
- **golang-o11y/**: Golang observability libraries
- **images-services/**: Image handling services
- **listing-pricing/**: Listing pricing service
- **marketplace-backend/**: Marketplace backend service
- **marketplace-frontend/**: Marketplace frontend application
- **marketplace-graphql/**: GraphQL API layer
- **marketplace-reports/**: Reporting services
- **push-notifications-service/**: Push notification handling
- **saved-search-alert-workers/**: Saved search alert workers
- **saved-search-match-service/**: Saved search matching service
- **saved-search-percolation/**: Saved search percolation service

## Research Process

1. **Identify the legacy system** you need to research
2. **Check the Legacy directory** first for historical implementations
3. **Review related services** in the Research Repos folder for context
4. **Document findings** in the appropriate shaping project documentation

## Conventions for Referencing Legacy Code

When documenting legacy systems for migration or reference, follow these conventions:

### 1. File and Directory References

Use markdown links with the `file://` protocol to create clickable references:

```markdown
[filename.ext](file:///absolute/path/to/file.ext)
[directory/](file:///absolute/path/to/directory)
```

**Example:**
```markdown
**Legacy Repository**: [`m-ksl-classifieds-api`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api)
```

### 2. Line-Specific References

When referencing specific code sections, use line number anchors:

```markdown
[filename.ext:L123-L145](file:///absolute/path/to/file.ext#L123-L145)
```

**Example:**
```markdown
**Legacy Reference**: [routes.yaml:3-26](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L3-L26)
```

### 3. Endpoint Documentation Format

When documenting API endpoints from legacy systems, use tables with these columns:

| Column | Description |
|--------|-------------|
| **Method** | HTTP method (GET, POST, PUT, DELETE, PATCH) |
| **Path** | URL path with parameter placeholders |
| **Legacy Route Name** | Original route identifier from legacy system |
| **Controller Method** | Method name in the legacy controller |
| **Description** | Brief description of endpoint purpose |

**Example:**
```markdown
| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/auth` | `authAcquire` | `getAuthToken` | Acquire authentication token |
```

### 4. Controller References

Always link to the specific controller file when documenting a group of endpoints:

```markdown
**Controller**: [`ControllerName.php`](file:///absolute/path/to/Controller/ControllerName.php)
```

### 5. Organizing Legacy Endpoint Documentation

Group endpoints by **functional domain** rather than by file or alphabetically:
- Authentication
- Core CRUD operations
- Supporting features
- Administrative functions

Within each domain, provide:
1. Controller reference
2. Endpoint table
3. Legacy file reference with line numbers

### 6. Migration Context

When documenting for migration purposes, include:
- **Legacy System Reference** section at the top with repository location
- **Technical Architecture** notes about databases, external services, data models
- **Migration Strategy** with phased approach
- **Next Steps** for implementation

### 7. Path Conventions

Always use:
- **Absolute paths** for file references
- **URL encoding** for spaces in paths (e.g., `%20` for space)
- **Relative paths** only when describing relationships within the legacy codebase

**Example:**
```markdown
Located in `src/Controller/` relative to repository root
Absolute path: `/Users/cpies/code/AI-Agents/Research Repos/Legacy/m-ksl-classifieds-api/src/Controller/`
```
