---
trigger: always_on
---

# Pattern and Structure Rule System

When working on this project, you must follow these mandatory protocols:

1. **Index First**: ALWAYS read the `.windsurf/rules_log/INDEX.md` file first before implementing any code or creating new rules to identify applicable patterns and navigate to relevant category folders.

2. **Rule Documentation**: Whenever you establish or discover a new pattern, structure, or convention in the codebase, IMMEDIATELY:
   - Log it as a new rule file in the appropriate category folder within the `.windsurf/rules_log/` directory (e.g., `.windsurf/rules_log/models/model_field_ordering.md`)
   - Ensure the rule is written to be applicable and effective for new projects and similar frameworks, maintaining consistent behavior across different project contexts
   - Update the `INDEX.md` file in the relevant category folder to reference this new rule
   - Update the top-level `.windsurf/rules_log/INDEX.md` to ensure the category is listed

3. **Rule Checking**: Before implementing any code change, feature, or architectural decision:
   - First check the top-level `.windsurf/rules_log/INDEX.md` to identify relevant category folders
   - Navigate to the `INDEX.md` file within the relevant category folder to locate specific rules
   - Review those specific rule files for detailed guidance, ensuring their applicability to the current project and similar frameworks

4. **Rule Creation Process**:
   - Place rule files in the appropriate category folder, creating a new folder if necessary (e.g., `.windsurf/rules_log/models/`, `.windsurf/rules_log/apis/`)
   - Name rule files descriptively (e.g., `model_field_ordering.md`, `api_response_structure.md`)
   - Format each rule file with:
     - Title and date created
     - Clear description of the pattern/structure, ensuring it is generalizable for use in new projects and similar frameworks
     - Code examples demonstrating correct implementation, using portable and framework-agnostic patterns where possible
     - Explanation of why this pattern should be followed and how it benefits consistency across projects

5. **Index Structure**:
   - Maintain the top-level `.windsurf/rules_log/INDEX.md` with a list of category folders (e.g., Models, Views, APIs)
   - For each category entry include:
     - Category name with link to the category’s `INDEX.md` file
     - Brief one-line description
     - Date created/modified
   - Within each category folder, maintain an `INDEX.md` with:
     - Rule name with link to the file
     - Brief one-line description
     - Date created/modified
     - Tags for searchability, including framework or project type for broader applicability

6. **Rule References**: When implementing code that follows an existing rule, explicitly reference the rule by citing its category and file (e.g., “See `.windsurf/rules_log/models/model_field_ordering.md`”).

7. **Rule Consistency**: Ensure all code you generate strictly adheres to established rules within the relevant category folders, verifying that rules maintain consistent effects across new projects and similar frameworks.

8. **Rule Evolution**: If you need to modify an existing rule:
   - Create a new version of the rule file in its category folder with clear explanation of what changed, why, and how it remains applicable to new projects and similar frameworks
   - Update the category’s `INDEX.md` to reflect this change
   - Update the top-level `.windsurf/rules_log/INDEX.md` if the category structure changes

9. **Category Folder Organization**:
   - Organize rules into category folders within `.windsurf/rules_log/` based on their domain (e.g., `models/`, `views/`, `apis/`)
   - Each category folder MUST contain an `INDEX.md` file to serve as a navigation hub for rules in that category
   - When creating a new category folder:
     - Add it to the top-level `.windsurf/rules_log/INDEX.md` with a link to the category’s `INDEX.md`
     - Initialize the category’s `INDEX.md` with the structure defined in rule #5
     - Provide a brief description of the category’s scope in both the top-level and category-specific `INDEX.md`, ensuring the category’s purpose is clear for use in new projects
   - Use consistent naming for category folders (lowercase, plural, no underscores, e.g., `models`, `apis`)

10. **Rule Portability**: When creating or updating rules:
    - Ensure rules are designed to be portable and effective across new projects and similar frameworks
    - Avoid project-specific assumptions, favoring generalizable patterns that maintain consistent behavior
    - Include notes in rule files on how the pattern applies to common frameworks or project types
    - Test rule applicability by considering its use in at least one other project context or framework

11. **Rule Enforcement**: Always enforce all active rules without deviation or hallucination at any point in time. Strictly adhere to documented patterns and structures in the rule files, ensuring no unauthorized variations are introduced.

12. **New Structure Handling**: If generating a new structure, pattern, or convention that falls outside the existing ruleset, IMMEDIATELY create a new rule for it following the processes in rules #2 and #4. This new rule can be updated or deleted later as needed, but must be documented to maintain consistency.

13. **Rule Pruning**: Automatically review and prune rules during rule checks or evolutions:
    - If a rule is no longer enforced or useful (e.g., due to framework changes or project evolution), mark it as "Stale" in the relevant category's `INDEX.md` and the top-level `INDEX.md`.
    - If a stale rule is confirmed obsolete, delete the rule file and remove its references from all `INDEX.md` files.
    - Include enforcement status updates in all `INDEX.md` files to reflect active, stale, or deleted rules, ensuring transparency and portability across projects.

This system ensures consistent code structure, self-documenting patterns, improved navigation through categorized rule organization, and portability of rules for use in new projects and similar frameworks throughout the project lifecycle.