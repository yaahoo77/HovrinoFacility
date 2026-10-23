# Prompt to paste into Lovable

Paste everything below the line into the Lovable chat.

---

On the `/documentation` page (create it if it does not exist), tell my phone game server that the player opened the page. Do not change anything else on the site.

Add this to the top of the page component:

```tsx
import { useEffect, useRef, useState } from 'react';

// inside the component:
const [ringing, setRinging] = useState(false);
const sent = useRef(false); // React may run effects twice in development; send once
useEffect(() => {
  if (sent.current) return;
  sent.current = true;
  fetch('/phonegame/documentation.php', { method: 'POST' })
    .then((r) => r.json())
    .then((d) => setRinging(d.status === 'planned'))
    .catch(() => {}); // no game server (e.g. in the Lovable preview): do nothing
}, []);
```

When `ringing` is true, show a small, unobtrusive line on the page: "☎ Your phone will ring soon." Show nothing otherwise. Keep the rest of the page exactly as it is.
