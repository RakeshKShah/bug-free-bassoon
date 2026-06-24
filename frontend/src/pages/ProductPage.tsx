import { useQuery } from "@tanstack/react-query";
import { useParams, useNavigate } from "react-router-dom";
import api, { formatPrice, type Product } from "../api/client";
import { useCart } from "../context/CartContext";
import { useAuth } from "../context/AuthContext";

export function ProductPage() {
  const { id } = useParams<{ id: string }>();
  const { add } = useCart();
  const { user } = useAuth();
  const navigate = useNavigate();

  const { data: product, isLoading } = useQuery({
    queryKey: ["product", id],
    queryFn: async () => {
      const { data } = await api.get<Product>(`/products/${id}`);
      return data;
    },
    enabled: !!id,
  });

  if (isLoading) return <p className="p-10 text-center">Loading...</p>;
  if (!product) return <p className="p-10 text-center">Product not found</p>;

  const soldOut = product.status === "sold_out" || product.stock_qty <= 0;
  const photo = Array.isArray(product.photos) ? product.photos[0] : "";

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <div className="grid gap-10 lg:grid-cols-2">
        <div className={`relative aspect-square overflow-hidden rounded-2xl bg-stone-100 ${soldOut ? "grayscale opacity-70" : ""}`}>
          {photo && <img src={photo} alt={product.title} className="h-full w-full object-cover" />}
          {soldOut && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/40">
              <span className="rounded-full bg-white px-6 py-3 text-lg font-semibold uppercase">Sold out</span>
            </div>
          )}
        </div>
        <div>
          <p className="text-sm uppercase tracking-wide text-teal-700">{product.category}</p>
          <h1 className="mt-2 font-serif text-4xl">{product.title}</h1>
          <p className="mt-2 text-stone-600">by <span className="font-medium text-teal-900">{product.store_name}</span></p>
          <p className="mt-6 text-3xl font-medium text-teal-900">{formatPrice(product.price_cents)}</p>
          <p className="mt-2 text-sm text-stone-500">{soldOut ? "Currently unavailable" : `${product.stock_qty} in stock`}</p>
          {product.description && <p className="mt-6 leading-relaxed text-stone-700">{product.description}</p>}
          <button
            type="button"
            disabled={soldOut}
            onClick={() => {
              if (!user) { navigate("/login"); return; }
              add({ product_id: product.id, title: product.title, price_cents: product.price_cents, photo }, 1);
              navigate("/cart");
            }}
            className="mt-8 rounded-full bg-teal-800 px-8 py-3 font-medium text-white hover:bg-teal-900 disabled:bg-stone-300"
          >
            {soldOut ? "Sold out" : "Add to cart"}
          </button>
        </div>
      </div>

      {product.reviews && product.reviews.length > 0 && (
        <section className="mt-16">
          <h2 className="font-serif text-2xl">Reviews</h2>
          <div className="mt-6 space-y-4">
            {product.reviews.map((r) => (
              <div key={r.id} className="rounded-xl border bg-white p-5">
                <span className="text-teal-800">{"★".repeat(r.rating)}</span>
                <p className="mt-2 text-stone-600">{r.body}</p>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
