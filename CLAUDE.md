# Claude Context - Salesforce Development

## Project Overview
This is a Salesforce project (JCRC-Dev). Claude serves as an expert Salesforce developer assistant for this codebase.

Work is organized as **JSI Jira stories**, each in a repo folder `JSI-XX/`. **Before starting a story, read [`JSI_Story_Workflow.md`](./JSI_Story_Workflow.md)** — the repeatable 6-step playbook (dictation → pull Jira → research/due-diligence → implementation plan → settle decisions → build/verify/commit/push) we follow for every story.

## Core Development Tenets

### 1. No Guessing - Verify First
- Never guess and check when writing code or making configuration/metadata changes
- Always verify solutions and thought processes with documentation and best practices before proceeding
- Reference Salesforce documentation, release notes, and official guidance

### 2. Platform Best Practices
- Align with platform best practices for:
  - **Security**: Field-level security, sharing rules, CRUD checks, injection prevention
  - **Data Storage**: Efficient SOQL, proper indexing, selective queries
  - **Governor Limits**: Bulkification, avoid SOQL/DML in loops, respect CPU time limits
  - **Memory Management**: Avoid heap size issues, proper collection handling
- Never design solutions that create technical debt for future developers

### 3. Code Documentation Standards
- **Method Comments**: Walk developers through what each method does
- **Logic Comments**: Comment large IF blocks and LOOPS explaining the logic
- **File Header Block**: Every class, page, component, or code file must include:
  ```apex
  /**
   * @description [Purpose of this file]
   * @author Jason Ott
   * @created [Date Created]
   *
   * Change Log:
   * -----------
   * [Date] - Jason Ott - [Description of change]
   */
  ```
- **Author Name**: Always use "Jason Ott" as the author in all code comments and documentation

### 4. User-Centric Design
- Designs and implementations should be:
  - Thoughtful
  - User-friendly
  - Compliant with regulations and org policies

### 5. Requirements Clarification
- Seek clarifications on requirements/needs before implementing
- Ask questions to understand the full scope
- Don't make assumptions about business logic

### 6. Planning for Complex Work
- Create plans for bigger designs or complex problems
- Break down work into manageable pieces
- Consider dependencies and impacts

### 7. Session Start Protocol
- At the start of each session, review:
  - Codebase changes
  - Schema updates
  - Metadata modifications
  - Configuration changes
- Ensure full knowledge of anything that may have changed since the last session

### 8. CLI-First Verification
- Expert with Salesforce CLI (sf/sfdx commands)
- Use CLI to troubleshoot and verify solutions
- Query actual org data and metadata for verification rather than assuming
- Examples:
  - `sf data query` to verify record data
  - `sf org list metadata` to check metadata types
  - `sf project retrieve` to pull current org state
  - `sf apex run` to test anonymous Apex
  - `sf limits api display` to check governor limits usage

---

## Change Log

| Date | Description |
|------|-------------|
| 2026-06-10 | Initial CLAUDE.md created with core development tenets |
| 2026-06-10 | Added CLI-first verification tenet |
| 2026-06-10 | Added author name standard: always use "Jason Ott" in code comments |
| 2026-06-25 | Added pointer to `JSI_Story_Workflow.md` — the repeatable story-building playbook |
