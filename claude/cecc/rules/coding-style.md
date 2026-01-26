# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate:

```javascript
// WRONG: Mutation
function updateUser(user, name) {
  user.name = name  // MUTATION!
  return user
}

// CORRECT: Immutability
function updateUser(user, name) {
  return {
    ...user,
    name
  }
}
```

## File Organization

MANY SMALL FILES > FEW LARGE FILES:
- High cohesion, low coupling
- 200-400 lines typical, 800 max
- Extract utilities from large components
- Organize by feature/domain, not by type

## Error Handling

ALWAYS handle errors comprehensively:

```typescript
try {
  const result = await riskyOperation()
  return result
} catch (error) {
  console.error('Operation failed:', error)
  throw new Error('Detailed user-friendly message')
}
```

## Input Validation

ALWAYS validate user input:

```typescript
import { z } from 'zod'

const schema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150)
})

const validated = schema.parse(input)
```

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Functions are small (<50 lines)
- [ ] Files are focused (<800 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Proper error handling
- [ ] No debug statements (console.log, println, print)
- [ ] No hardcoded values
- [ ] No mutation (immutable patterns used)

---

## Kotlin Style Guide

### Null Safety

ALWAYS use Kotlin's null safety features:

```kotlin
// WRONG: Platform type or unsafe
val name = user!!.name

// CORRECT: Safe call with fallback
val name = user?.name ?: "Unknown"

// CORRECT: Scope function for complex logic
user?.let { u ->
    processUser(u.name, u.email)
}
```

### Data Classes

PREFER data classes for DTOs and value objects:

```kotlin
// CORRECT: Immutable data class
data class UserDto(
    val id: UUID,
    val email: String,
    val name: String
)

// CORRECT: With default values
data class CreateUserRequest(
    val email: String,
    val name: String,
    val role: Role = Role.USER
)
```

### Extension Functions

USE extension functions for utility operations:

```kotlin
// CORRECT: Extension for clarity
fun String.toSlug(): String =
    this.lowercase()
        .replace(Regex("[^a-z0-9]+"), "-")
        .trim('-')

val slug = title.toSlug()
```

### Coroutines

PREFER structured concurrency:

```kotlin
// CORRECT: Scoped coroutine
suspend fun fetchAllData(): CombinedData = coroutineScope {
    val users = async { fetchUsers() }
    val orders = async { fetchOrders() }
    CombinedData(users.await(), orders.await())
}
```

### Kotlin Code Quality Checklist

- [ ] No `!!` operator (use `?.` or `?:` or `requireNotNull`)
- [ ] No `var` where `val` works
- [ ] No mutable collections where immutable works
- [ ] Data classes for DTOs
- [ ] Sealed classes for state machines
- [ ] Extension functions over utility classes
- [ ] No println() debug statements

---

## Python Style Guide

### Type Hints

ALWAYS use type hints (Python 3.10+ syntax):

```python
# WRONG: No type hints
def process_user(user, name):
    return user.update(name)

# CORRECT: Full type hints
def process_user(user: User, name: str) -> User:
    return user.model_copy(update={"name": name})

# CORRECT: Optional and Union (Python 3.10+)
def find_user(user_id: UUID) -> User | None:
    return db.get(user_id)
```

### Pydantic Models

USE Pydantic for validation and DTOs:

```python
from pydantic import BaseModel, EmailStr, Field

# CORRECT: Pydantic model with validation
class CreateUserRequest(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=100)
    age: int = Field(ge=0, le=150)
```

### Async/Await

PREFER async for I/O operations:

```python
# CORRECT: Async function
async def fetch_user(user_id: UUID) -> User:
    return await db.get(User, user_id)

# CORRECT: Concurrent fetching
async def fetch_all() -> tuple[Users, Orders]:
    users, orders = await asyncio.gather(
        fetch_users(),
        fetch_orders()
    )
    return users, orders
```

### Error Handling

USE explicit exception types:

```python
# CORRECT: Custom exceptions
class UserNotFoundError(Exception):
    def __init__(self, user_id: UUID) -> None:
        super().__init__(f"User not found: {user_id}")
        self.user_id = user_id

# CORRECT: Handling with specific types
async def get_user(user_id: UUID) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise UserNotFoundError(user_id)
    return user
```

### Python Code Quality Checklist

- [ ] Type hints on all functions
- [ ] Pydantic for external data validation
- [ ] No bare `except:` clauses
- [ ] Async for I/O operations
- [ ] f-strings over .format() or %
- [ ] No print() statements (use logging)
- [ ] Pathlib over os.path
