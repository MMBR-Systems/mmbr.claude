# Figma MCP Workflow

> **Status:** Testado e validado
> **Date:** 2026-04-01
> **MCP Server:** Official Figma MCP (`mcp.figma.com/mcp`)

---

## Setup

### 1. MCP Server (already configured)

```bash
# Add official Figma MCP (HTTP transport)
claude mcp add --transport http figma https://mcp.figma.com/mcp
```

### 2. Authenticate

```bash
# Inside Claude Code, the MCP will prompt OAuth login automatically
# A browser window opens for Figma authorization
# After auth, tools become available in the session
```

### 3. Verify

```bash
claude mcp list
```

Expected output:
```
plugin:figma:figma → https://mcp.figma.com/mcp (HTTP) - Connected
```

> **Note:** Do NOT use `figma-developer-mcp` (community). The official MCP provides better output with React+Tailwind code generation, screenshots, and design tokens.

---

## Architecture

```
Figma (design source of truth)
  ↓
Figma MCP (structured data via mcp.figma.com)
  ↓
Claude Code (AI agent)
  ↓
Codebase (Next.js / React / Tailwind)
```

---

## Available Tools

### `get_figma_data` - File Structure
Get file overview and page list. No nodeId required.

```
Use: Discover pages, understand file structure
Returns: Page names, IDs, component metadata
```

### `get_metadata` - Node Structure
Get XML tree of a page or frame with node IDs, names, positions, and sizes.

```
Use: Find specific frames, discover node IDs
Returns: XML with all child nodes
Params: fileKey, nodeId
```

### `get_design_context` - Design Details (PRIMARY TOOL)
Get full design context: screenshot, React+Tailwind code, styles, tokens.

```
Use: Implement a specific screen or component
Returns: Screenshot, generated code, typography, colors, spacing
Params: fileKey, nodeId, disableCodeConnect=true
```

### `get_screenshot` - Visual Preview
Get a screenshot of any node.

```
Use: Quick visual check without code generation
Returns: Screenshot image
Params: fileKey, nodeId
```

### `search_design_system` - Component Search
Search for components, variables, and styles across libraries.

```
Use: Find reusable components
Returns: Component names, keys, library info
Params: query, fileKey
```

---

## Workflow: Implementing a Screen

### Step 1 - Discover frames

Use `get_metadata` on a page to find all frames:

```
get_metadata(fileKey: "<fileKey>", nodeId: "<pageId>")
→ Find mobile frames (width 393 or 412)
→ Find desktop frames (width 1440)
```

### Step 2 - Get design context

Use `get_design_context` on a specific frame:

```
get_design_context(fileKey: "<fileKey>", nodeId: "<frameId>", disableCodeConnect: true)
```

Returns:
- Screenshot of the frame
- React + Tailwind code (reference, not final)
- Typography specs (font family, size, weight, line-height)
- Color values (hex + CSS variables)
- Spacing values (padding, gap, margin)
- Shadow definitions
- Border radius values

### Step 3 - Adapt to project

The generated code is a **reference**, not production code. Adapt:

1. Remove browser chrome (status bar, Safari bar)
2. Use project's component library
3. Map CSS variables to project tokens
4. Follow project conventions (file naming, folder structure)

---

## Tips

### Finding mobile frames
```python
# Mobile frames have width 393 (iPhone) or 412 (Android)
# Search metadata for frames with width 300-500 and height > 600
```

### Rate limits
- The MCP has rate limits. Avoid parallel calls.
- Use `get_metadata` first (lighter), then `get_design_context` for specific frames.
- Avoid using `figma-developer-mcp` (community) — hits limits faster.

### Code Connect (future)
When the project has components built, Code Connect can map Figma components to code:

```bash
npm install -g @figma/code-connect
figma connect init
```

This improves code generation by reusing existing components instead of generating new ones. Not needed until you have a component library in place.

---

## Quick Reference Commands

```
# Get file structure
get_figma_data(fileKey: "<fileKey>", depth: 1)

# Get page metadata (find frames)
get_metadata(fileKey: "<fileKey>", nodeId: "<pageId>")

# Get design for implementation
get_design_context(fileKey: "<fileKey>", nodeId: "<frameId>", disableCodeConnect: true)

# Screenshot only
get_screenshot(fileKey: "<fileKey>", nodeId: "<frameId>")

# Search components
search_design_system(query: "button", fileKey: "<fileKey>")
```

> **Project-specific data** (file keys, node IDs, design tokens) should live in the project's own docs folder (e.g. `mmbr-frontend/docs/`).

---

_Last updated: 2026-04-01_
