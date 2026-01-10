# AdditionalDocumentation Index

## How to use this index
1) Identify which UI area you are changing (e.g., navigation, forms, charts, glass surfaces).
2) Open the matching Apple doc(s) below.
3) Extract 3–5 actionable rules before coding.
4) Validate with `scripts/design-check.sh`.

---

## Docs

### AppIntents-Updates.md
Updates to App Intents, including new system integrations, UX refinements, snippets, and Spotlight support.
Use this when:
- Adding intents, shortcuts, or Spotlight indexing.
- Integrating system-level intent behaviors.

### AppKit-Implementing-Liquid-Glass-Design.md
AppKit guidance for implementing Liquid Glass using NSGlassEffectView/Container, customization, and interaction.
Use this when:
- Translating Liquid Glass patterns to macOS/AppKit.
- Referencing glass behavior and best practices across platforms.

### Foundation-AttributedString-Updates.md
Foundation updates for AttributedString: alignment, writing direction, line height, selection, and SwiftUI integration.
Use this when:
- Styling rich text or notes.
- Managing text layout, selection, or editing behavior.

### FoundationModels-Using-on-device-LLM-in-your-app.md
Using Apple on-device LLMs: sessions, prompts, tool calling, streaming, and constraints.
Use this when:
- Evaluating on-device AI features (only if explicitly requested).

### Implementing-Assistive-Access-in-iOS.md
How to enable Assistive Access, adjust UI, and test accessibility-specific experiences.
Use this when:
- Ensuring Assistive Access compatibility or simplified UI modes.

### Implementing-Visual-Intelligence-in-iOS.md
Visual Intelligence APIs: semantic descriptors, intent value queries, and deep linking with AppEntity.
Use this when:
- Adding visual search or system-driven semantic queries.

### MapKit-GeoToolbox-PlaceDescriptors.md
Place descriptors, representations, and geocoding workflows using MapKit and GeoToolbox.
Use this when:
- Adding map-based surf spot selection or geocoding features.

### StoreKit-Updates.md
StoreKit updates, subscription offer UI, transaction updates, and testing flows.
Use this when:
- Adding in-app purchases or subscription UI (only if requested).

### Swift-Charts-3D-Visualization.md
Using 3D charts and surface plots with Swift Charts.
Use this when:
- Considering 3D data visualization for stats or trends.

### Swift-Concurrency-Updates.md
Swift concurrency updates around data-race safety, global state, and background work.
Use this when:
- Implementing async workflows or background processing.

### Swift-InlineArray-Span.md
New InlineArray and Span types for low-overhead collections and memory access.
Use this when:
- Optimizing performance-critical loops or memory-heavy data processing.

### SwiftData-Class-Inheritance.md
Guidance for SwiftData inheritance, querying, and polymorphic relationships.
Use this when:
- Considering model hierarchies or shared base classes.

### SwiftUI-AlarmKit-Integration.md
AlarmKit integration in SwiftUI: authorization, scheduling, and UI customization.
Use this when:
- Adding alarms or timers (only if requested).

### SwiftUI-Implementing-Liquid-Glass-Design.md
SwiftUI Liquid Glass APIs: glassEffect, containers, interactive glass, and button styles.
Use this when:
- Building or refining glass cards, chips, or buttons.

### SwiftUI-New-Toolbar-Features.md
SwiftUI toolbar customization, new placements, and search integration.
Use this when:
- Adjusting toolbar layout, search behavior, or navigation affordances.

### SwiftUI-Styled-Text-Editing.md
Text styling and editing in SwiftUI, including TextEditor and AttributedString workflows.
Use this when:
- Designing notes fields or rich text editing surfaces.

### SwiftUI-WebKit-Integration.md
Embedding WebKit in SwiftUI with WebView/WebPage, configuration, and navigation.
Use this when:
- Embedding web content (only if requested).

### UIKit-Implementing-Liquid-Glass-Design.md
UIKit Liquid Glass patterns: glass effects, combined elements, scroll edge effects, and toolbars.
Use this when:
- Working in UIKit or bridging UIKit surfaces into SwiftUI.

### WidgetKit-Implementing-Liquid-Glass-Design.md
Liquid Glass in WidgetKit, rendering modes, and background treatments.
Use this when:
- Building widgets or widget styling.

### Widgets-for-visionOS.md
Widget mounting styles, textures, and rendering modes for visionOS.
Use this when:
- Targeting visionOS widgets or cross-platform widget design.

### INDEX.md
This index of the Apple documentation in `AdditionalDocumentation/`.
Use this when:
- Choosing which Apple doc to consult for a UI change.
