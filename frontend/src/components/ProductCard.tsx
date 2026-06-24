import { Link } from "react-router-dom";
import { formatPrice, type Product } from "../api/client";

export function ProductCard({ product }: { product: Product }) {
  const soldOut = product.status === "sold_out" || product.stock_qty <= 0;
  const photo = Array.isArray(product.photos) ? product.photos[0] : "";

  return (
    <Link
      to={`/product/${product.id}`}
      className={`block overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm transition hover:shadow-md ${
        soldOut ? "opacity-60 grayscale" : ""
      }`}
    >
      <div className="relative aspect-square bg-stone-100">
        {photo && <img src={photo} alt={product.title} className="h-full w-full object-cover" />}
        {soldOut && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/40">
            <span className="rounded-full bg-white px-4 py-2 text-sm font-semibold uppercase">
              Sold out
            </span>
          </div>
        )}
      </div>
      <div className="p-4">
        <p className="text-xs uppercase tracking-wide text-teal-700">{product.category}</p>
        <h3 className="mt-1 font-serif text-lg">{product.title}</h3>
        <p className="text-sm text-stone-500">by {product.store_name}</p>
        <p className="mt-2 font-medium text-teal-900">{formatPrice(product.price_cents)}</p>
      </div>
    </Link>
  );
}
