import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import api, { formatPrice } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { Navigate } from "react-router-dom";

type Order = {
  id: string;
  status: string;
  totalCents: number;
  createdAt: string;
  items: { id: string; product: { title: string }; qty: number; review: unknown }[];
};

export function OrdersPage() {
  const { user } = useAuth();
  const [params] = useSearchParams();
  const successId = params.get("success");

  const { data: orders = [] } = useQuery({
    queryKey: ["orders"],
    queryFn: async () => (await api.get<Order[]>("/orders")).data,
    enabled: !!user,
  });

  if (!user) return <Navigate to="/login" replace />;

  async function markDelivered(orderId: string) {
    await api.post(`/orders/${orderId}/deliver`);
    window.location.reload();
  }

  return (
    <div className="mx-auto max-w-4xl px-4 py-10">
      <h1 className="font-serif text-3xl">Your orders</h1>
      {successId && (
        <p className="mt-4 rounded-lg bg-green-50 px-4 py-3 text-green-800">Order placed successfully!</p>
      )}
      {orders.length === 0 ? (
        <p className="mt-8 text-stone-500">No orders yet.</p>
      ) : (
        <div className="mt-8 space-y-6">
          {orders.map((o) => (
            <div key={o.id} className="rounded-xl border bg-white p-6">
              <div className="flex justify-between">
                <div>
                  <p className="font-medium">Order #{o.id.slice(-8)}</p>
                  <p className="text-sm text-stone-500">{new Date(o.createdAt).toLocaleDateString()} · {o.status}</p>
                </div>
                <p className="font-semibold text-teal-900">{formatPrice(o.totalCents)}</p>
              </div>
              <ul className="mt-4 space-y-1 border-t pt-4 text-sm">
                {o.items.map((i) => (
                  <li key={i.id}>{i.qty}x {i.product.title}</li>
                ))}
              </ul>
              {o.status === "SHIPPED" && (
                <button type="button" onClick={() => markDelivered(o.id)} className="mt-4 rounded-full bg-teal-800 px-4 py-2 text-sm text-white">
                  Confirm delivery (enables reviews)
                </button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
