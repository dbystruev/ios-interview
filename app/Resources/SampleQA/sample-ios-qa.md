# Sample iOS Interview Q&A

Bundled starter set. Import more `.md` files from Library → Import.

## Swift Programming (3 Questions)

1. **What's the difference between weak and unowned references?**
   - `weak`: does not increase the reference count, becomes nil when the referenced object is deallocated. Use when the reference may become nil.
   - `unowned`: assumes the object outlives the reference; faster, but crashes if accessed after deallocation.

2. **When do retain cycles occur?**
   - When two or more objects hold strong references to each other, e.g. a view controller holding a closure that captures `self` strongly.
   - Break cycles with `[weak self]` or `[unowned self]` capture lists.

3. **Explain the difference between structs and classes in Swift.**
   - Structs are value types: copied on assignment, good for immutable data models, thread-safe by default.
   - Classes are reference types: shared identity, support inheritance, need care with thread safety.

## iOS Basics (3 Questions)

1. **What's the difference between viewDidLoad and viewWillAppear?**
   - `viewDidLoad`: called once after the view is loaded; good for one-time setup.
   - `viewWillAppear`: called every time the view is about to appear; good for refreshing data.

2. **How do you prevent memory leaks in UIViewController?**
   - Use `[weak self]` in closures, remove observers in `deinit`, invalidate timers, cancel network requests.

3. **When should you use struct vs class?**
