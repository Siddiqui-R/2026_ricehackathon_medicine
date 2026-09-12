# Reva UI follow-ups

Requested September 12, 2026 through browser annotations. Implemented following the subsequent request to complete these changes alongside the repairs.

- [x] **Overview slogan:** replace “A clearer picture. A more prepared you.” with exactly **“Making every appointment meaningful”**.
- [x] **Demo labels:** remove visible fictional/synthetic labels throughout the demo, including clinician and clinic suffixes, profile name/badge, allergies, medications, and conditions. Retain internal demo identity so account separation and source handling continue to work.
- [x] **Preparation action:** move **“Prepare for this visit”** from the next-appointment card footer into the highlighted “A little preparation goes a long way” section. Preserve its appointment destination and responsive layout. The annotation said “video”; the selected card and existing control identify the visit action.
- [x] **Medical profile subtitle:** remove “The details you want handy at every appointment.”
- [x] **Demo-person switcher:** add a small “Switch demo account” control near the sidebar avatar, with several distinct example people and matching medical profiles/history. Keep it clearly scoped to demo examples and preserve separate state when changing people.

Reference screens: Overview (`#/summary`) at 774×749 and Medical profile (`#/profile`) at 917×749. Verify tablet rail labels and narrow-screen layout when implementing these items.

Demo switching uses whitelisted URL IDs and separate IndexedDB databases for Jordan Avery, Maya Patel and Alex Chen. The existing Jordan database is retained; new people have their own authored notes and appointments. Demo labels are cleaned for display while internal provenance, source quotations, transcripts and original files remain intact.
