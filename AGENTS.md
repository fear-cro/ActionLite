# ActionLITE repository guidelines

- Keep the game addon in the top-level `ActionLITE/` folder with its existing filename capitalization.
- Keep the Word patch notes in the repository root, alongside `ActionLITE/`, and outside the addon folder. Use that document as the sole release changelog.
- Do not add `INSTALL.txt`, `PATCH_NOTES.txt`, or `THIRD_PARTY_LICENSES.txt` to this repository or future build packages. Installation directions belong in `README.md`.
- Use `Fear-Cro` for first-party author names and credits, including Cast Trail comments and addon metadata. Check current text files and document metadata before publishing.
- Preserve this structure in future builds: addon files inside `ActionLITE/`; Word patch notes in the parent folder. Do not place release documents inside the game addon.
- Keep release version metadata and root patch notes consistent. The current release version is `1.0.23`.
