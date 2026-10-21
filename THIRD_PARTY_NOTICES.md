# Third-party software and assets

The [MIT license](LICENSE) covers repository contributions, not third-party
dependencies, container images, database engines, fonts, or trademarks.
Those components retain their respective licenses and notices.

Dependency versions are declared in the .NET project files and
[frontend manifest](src/frontend/package.json); resolved frontend versions are
recorded in the [lockfile](src/frontend/package-lock.json).

## Distribution considerations

- The API uses NPOI for spreadsheet processing. Its project file explicitly
  accepts the NPOI OSMF agreement. The 2.8.0 package describes its source as
  Apache-2.0 and a maintenance fee for upstream binaries used in revenue-generating
  activities by users with annual gross revenue of at least US$10,000, subject
  to its exemptions. Review the package's `OSMFEULA.txt` before commercial use
  or redistribution; this repository's MIT license does not waive those terms.
- Oracle, SQL Server, and other database clients and demo database engines have
  their own license terms. A sample lab or container reference does not grant a
  license to use or redistribute proprietary database software.
- Preserve the license and notice files supplied by dependencies when packaging
  applications or containers. Review transitive dependencies as well as direct
  references.
- Product names and logos are the property of their respective owners. This
  project does not imply vendor endorsement or official product support.

Before distributing binaries or container images, generate an inventory from the
exact restored dependencies and container images, review their license terms,
and include all required notices. This document is guidance, not a replacement
for that release-specific inventory or legal review.
