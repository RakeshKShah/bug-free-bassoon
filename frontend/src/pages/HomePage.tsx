import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import api from "../api/client";
import { ProductCard } from "../components/ProductCard";
import type { Product } from "../api/client";

const CATEGORIES = ["jewelry", "ceramics", "textiles"];

export function HomePage() {
  const [keyword, setKeyword] = useState("");
  const [category, setCategory] = useState("");
  const [search, setSearch] = useState({ keyword: "", category: "" });

  const { data: products = [], isLoading } = useQuery({
    queryKey: ["products", search],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (search.keyword) params.set("keyword", search.keyword);
      if (search.category) params.set("category", search.category);
      const { data } = await api.get<Product[]>(`/products?${params}`);
      return data;
    },
  });

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <section className="mb-10 text-center">
        <h1 className="font-serif text-4xl font-semibold text-teal-950 md:text-5xl">
          Handmade goods from local artisans
        </h1>
        <p className="mx-auto mt-4 max-w-2xl text-lg text-stone-600">
          Discover jewelry, ceramics, and textiles crafted with care.
        </p>
      </section>

      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          setSearch({ keyword, category });
        }}
      >
        <div className="flex gap-2">
          <input
            type="search"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            placeholder="Search handmade goods..."
            className="flex-1 rounded-full border border-stone-300 px-5 py-3 outline-none focus:border-teal-600"
          />
          <button type="submit" className="rounded-full bg-teal-800 px-6 py-3 text-white hover:bg-teal-900">
            Search
          </button>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => { setCategory(""); setSearch({ keyword, category: "" }); }}
            className={`rounded-full px-4 py-1.5 text-sm ${!category ? "bg-teal-800 text-white" : "bg-stone-100"}`}
          >
            All
          </button>
          {CATEGORIES.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => { setCategory(c); setSearch({ keyword, category: c }); }}
              className={`rounded-full px-4 py-1.5 text-sm capitalize ${category === c ? "bg-teal-800 text-white" : "bg-stone-100"}`}
            >
              {c}
            </button>
          ))}
        </div>
      </form>

      <section className="mt-10">
        {isLoading ? (
          <p className="text-center text-stone-500">Loading...</p>
        ) : products.length === 0 ? (
          <p className="rounded-2xl border border-dashed p-12 text-center text-stone-500">No products found.</p>
        ) : (
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {products.map((p) => <ProductCard key={p.id} product={p} />)}
          </div>
        )}
      </section>
    </div>
  );
}
