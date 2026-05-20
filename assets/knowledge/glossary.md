# Domain glossary

> Terms used in this project's UI, code, and business logic. The coding agent references these to use correct names in code, comments, UI strings, and commit messages.
>
> **Format:** Term | Meaning | Where it appears
>
> Delete the examples below once you've added real terms.

| Term | Meaning | Where it appears |
|------|---------|------------------|
| <!-- TODO --> | <!-- TODO --> | <!-- TODO --> |

## Examples (delete these rows when you fill in real terms)

| Patient | A registered end-user ordering medical supplies | `va_patient_register`, `va_user`, `User` entity bundle |
| Therapy | Treatment category that groups products by medical condition | Content type `therapy`, taxonomy `therapy_category` |
| Variant | A purchasable product variation (size, configuration) | Content type `variant`, `va_commercetools` |
| Infothek | Knowledge base section | `va_infothek` module, `/infothek` route |

## Naming conventions for new code

When adding new entities/fields/routes that involve domain terms, use the German term where the codebase already does (e.g. `infothek`, `therapie`) — do not anglicise unless creating something net-new.
