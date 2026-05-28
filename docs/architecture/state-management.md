# State Management

> The web platform does not use Redux, Zustand, Jotai, or any state
> management library. This doc explains the patterns we use instead and
> when each applies.

## What we use

| Pattern | When | Where |
|---------|------|-------|
| **Server component props** | Initial data fetched on the server | `(protected)/layout.tsx` fetches plants + user → passes to `ProtectedShell` |
| **React Context** | Cross-component state that's short-lived and derives from something external | `SelectedPlantProvider` wraps the shell |
| **`useSyncExternalStore`** | Subscribing to browser storage (sessionStorage, localStorage) | Inside `useSelectedPlant` |
| **React hooks (`useState`, `useReducer`)** | Component-local UI state | Anywhere |
| **Next.js server actions** | Mutations that don't need a full API route | Not yet used in the web platform |

## Case study: Selected plant

### The problem

Multiple components need to know which plant is currently selected:
- `Sidebar` — to fetch the threads list for that plant
- `MobileNavbar` — to display the plant name and show the dropdown
- Chat pages — to include the plant context in API calls

Before the refactor, each of these owned its own `useState` mirror of `selectedPlantId` + a `useEffect` to hydrate from `sessionStorage`. Three copies of the same value kept in sync through a fragile mix of callbacks and `storage` events.

### The solution: `useSelectedPlant`

Single source of truth backed by `useSyncExternalStore` over sessionStorage:

```tsx
// lib/hooks/useSelectedPlant.tsx
const subscribers = new Set<() => void>();

function subscribe(callback: () => void): () => void {
  subscribers.add(callback);
  window.addEventListener("storage", callback);
  return () => {
    subscribers.delete(callback);
    window.removeEventListener("storage", callback);
  };
}

function getSnapshot(): string {
  return sessionStorage.getItem(PLANT_STORAGE_KEY) ?? "";
}

export function SelectedPlantProvider({ plants, children }) {
  const storedId = useSyncExternalStore(subscribe, getSnapshot, () => "");
  const effectivePlantId =
    storedId && plants.some((p) => p.id === storedId)
      ? storedId
      : (plants[0]?.id ?? "");

  const setSelectedPlantId = useCallback((plantId: string) => {
    sessionStorage.setItem(PLANT_STORAGE_KEY, plantId);
    subscribers.forEach((cb) => cb());
  }, []);

  return (
    <SelectedPlantContext.Provider value={{ ... }}>
      {children}
    </SelectedPlantContext.Provider>
  );
}
```

### Why `useSyncExternalStore`?

1. **Single source of truth**: sessionStorage is the source, all consumers read from it.
2. **Same-tab sync**: a `Set<() => void>` of subscribers + `notifySubscribers()` after every write. The `storage` event only fires cross-tab, so we need our own pub-sub for same-tab updates.
3. **Cross-tab sync**: `window.addEventListener("storage", callback)` handles cross-tab updates for free.
4. **React 19 concurrent rendering**: `useSyncExternalStore` is specifically designed for subscribing to external stores without tearing.
5. **No `setState` in `useEffect`**: eliminates the React lint rule violation that the naive "hydrate on mount" pattern triggers.

### Why Context and not just a standalone hook?

The `plants` list comes from the server component (`(protected)/layout.tsx`) via props. The hook needs to know which plants are valid so it can heal stale sessionStorage entries. Context makes the provider's `plants` prop available to any descendant without prop drilling.

### Stale-healing

```tsx
useEffect(() => {
  const current = sessionStorage.getItem(PLANT_STORAGE_KEY);
  const isStale = current && !plants.some((p) => p.id === current);
  if (!current || isStale) {
    sessionStorage.setItem(PLANT_STORAGE_KEY, plants[0].id);
    notifySubscribers();
  }
}, [plants]);
```

If the stored plant id no longer exists in the user's plant list (e.g., they were unassigned), overwrite it with the first available plant so storage stays consistent with the UI.

## Why we don't use a state library

| Concern | Why it's not needed |
|---------|---------------------|
| "We need global state" | We have server component props + React Context. That covers 95% of cases. |
| "State changes across many components" | Only plant selection is truly cross-component, and `useSelectedPlant` handles it. |
| "We need time-travel debugging" | Not a priority; React DevTools is enough. |
| "We need middleware" | API calls go through `qbricksFetch` / route handlers — that's where cross-cutting concerns live. |
| "We need optimistic updates" | React 19 has `useOptimistic` built in. |

Adding a library would be premature complexity for a team of 2 frontend devs.

## What to do when you need new shared state

1. **Is it initial data from the server?** Fetch in a server component, pass as props.
2. **Is it derived from something in storage (cookies, localStorage, sessionStorage)?** Use `useSyncExternalStore` wrapped in a Context, like `useSelectedPlant`.
3. **Is it short-lived UI state (modal open, form draft)?** Use `useState` locally. Lift only if siblings need it.
4. **Is it mutation state (form submission, optimistic update)?** Use `useTransition` / `useOptimistic` / server actions.

**Never** create a third `useState` mirror of something that already has a single source of truth.

## Reading

- `lib/hooks/useSelectedPlant.tsx` — the canonical example
- `lib/constants/storage.ts` — single definition of `PLANT_STORAGE_KEY`
- `components/layout/ProtectedShell.tsx` — how the provider is wired in
- `components/layout/Sidebar.tsx` + `components/layout/MobileNavbar.tsx` — how consumers use the hook
