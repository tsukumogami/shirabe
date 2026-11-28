<!-- decision:start id="package-licence" status="undecided" -->
### Decision: Package licence

**Context**
The package wraps two libraries and is about to be published to a public
registry for the first time. Nothing in the repository names a licence, and
the wrapped libraries are both MIT-licensed.

**Question**
Which licence should the package be published under?

**Recommendation: MIT**
It matches the licence of the two libraries the package wraps, so a user
reads one licence across the stack.

**Alternatives Considered**
- **MIT**: permissive, short. Still in play: it matches the wrapped libraries.
- **Apache-2.0**: permissive with a patent grant. Still in play: the grant
  protects users, and the wrapped libraries do not offer one.

**What Would Settle It**
The owner's answer to whether the package should carry a patent grant. Once
published, the licence of a released version cannot be taken back, so the
choice is costly to undo.
<!-- decision:end -->
