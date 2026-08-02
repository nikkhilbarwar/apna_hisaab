# Final Windows Case-Sensitivity Fix: Comprehensive Import Unification

The user is still experiencing "argument_type_not_assignable" errors on Windows. This is caused by a case-sensitivity mismatch in file paths (e.g., `E:\` vs `e:\`) when Dart encounters a mixture of **Package Imports** and **Relative Imports**.

## User Review Required

> [!IMPORTANT]
> I will perform a mandatory, project-wide conversion of **all remaining relative imports** to package-absolute imports. This includes "same-directory" imports like `import 'foo.dart';` which I missed in the previous pass. This is a purely structural change and will not affect app logic.

## Proposed Changes

### 1. Global Import Overhaul

#### [MODIFY] lib/**/*.dart
- I will scan every file in the `lib` directory.
- Any import that starts with `.` or doesn't start with `package:` or `dart:` will be converted to `package:apna_hisaab/...`.
- **Target Files**:
    - `lib/providers/sync_provider.dart` (Confirmed problematic)
    - `lib/services/print_service.dart` (Confirm relative imports)
    - `lib/screens/**/*` (Confirmed many relative imports)

### 2. Provider Context Safety

#### [MODIFY] lib/providers/sync_provider.dart
- Ensure all calls to `Provider.of` use `context.mounted` checks.
- Clean up any duplicate imports if found during the overhaul.

## Verification Plan

### Automated Verification
- I will run a final `grep` to ensure zero relative imports remain in the `lib/` directory.

### Manual Verification
- Run `flutter run -d windows`.
- Confirm that the "argument_type_not_assignable" error is gone.
- Verify that the app syncs and restores without "Restore Failed" (now that types are unified).
