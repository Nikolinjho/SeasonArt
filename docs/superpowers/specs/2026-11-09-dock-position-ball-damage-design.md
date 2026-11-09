# Dock snow placement and snowball damage

Approved in chat on 9 November 2026 (MSK).

One snow-only menu, “Расположение снега”, selects mutually exclusive “Над Dock” or “Под Dock”. The default remains above. Persist the choice per user profile and apply it to every screen, including screens attached later. Below mode lets snow pass behind the Dock and accumulate on the screen floor, retaining collisions with other windows. The solid Dock still supports winter toys. Changing placement moves existing Dock snow to the ground without duplicating mass. Changing back routes ground snow out of the Dock footprint through the existing mass-preserving path. Other particle modes retain their previous behavior.

Snowballs retain local dents and an uneven outline after a hard landing. Damage grows with impact speed and is bounded, so the ball remains usable and stackable. Gentle placement produces no damage. Damage follows a ball when rolled, dragged or assembled into a snowman. The contact point remains supported rather than floating after the lower contour is compressed. A small amount of snow breaks off into existing particle rendering. Repeated resting updates must not damage or shed snow again.

Verification covers persisted settings, falling particles in both placements, mass preservation while switching, independent window collisions, impact strength, gentle placement, repeated updates, assembly preservation and actual rendered silhouette. Synthetic previews do not establish native acceptance.
