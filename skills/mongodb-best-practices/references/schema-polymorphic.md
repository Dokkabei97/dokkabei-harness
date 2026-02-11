---
title: Use Polymorphic Pattern for Heterogeneous Documents in Same Collection
impact: MEDIUM-HIGH
impactDescription: Simplified queries, single collection for related entity types
tags: polymorphic-pattern, single-collection, entity-type, schema-design
---

## Use Polymorphic Pattern for Heterogeneous Documents in Same Collection

The Polymorphic Pattern stores documents with different structures in the same collection, identified by a type discriminator field. Useful when entities share common fields but have type-specific attributes.

**Incorrect (separate collections for each product type):**

```javascript
// Separate collections — complex application logic, multiple queries
db.electronics.find({ brand: "Samsung" });
db.clothing.find({ brand: "Nike" });
db.books.find({ author: "Kim" });
// 3 separate queries to search across all products
```

**Correct (single collection with type discriminator):**

```javascript
// All products in one collection with a type field
db.products.insertMany([
  {
    type: "electronics",
    name: "Galaxy S25",
    brand: "Samsung",
    price: 1200000,
    specs: { ram: "12GB", storage: "256GB", battery: 5000 }
  },
  {
    type: "clothing",
    name: "Air Max 90",
    brand: "Nike",
    price: 159000,
    specs: { size: "270", color: "white", material: "mesh" }
  },
  {
    type: "book",
    name: "MongoDB in Action",
    brand: "Manning",
    price: 45000,
    specs: { isbn: "978-1617291609", pages: 480 }
  }
]);

// Single query across all types
db.products.find({ brand: "Samsung" });

// Type-specific query
db.products.find({ type: "electronics", "specs.ram": "12GB" });

// Partial index for type-specific queries
db.products.createIndex(
  { "specs.ram": 1 },
  { partialFilterExpression: { type: "electronics" } }
);
```

Reference: [Polymorphic Pattern](https://www.mongodb.com/developer/products/mongodb/polymorphic-pattern/)
