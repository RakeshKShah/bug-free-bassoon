import { useQuery, useQueryClient } from "@tanstack/react-query";
import api, { formatPrice } from "../api/client";
import { useAuth } from "../context/AuthContext";
import { Navigate } from "react-router-dom";

type Dashboard = {
  store_name: string;
  bio: string;
  status: string;
  products: { id: string; title: string; priceCents: number; stockQty: number; status: string }[];
  orders: { id: string; order_id: string; product_title: string; qty: number; buyer_email: string; order_status: string; seller_payout_cents: number }[];
  total_earnings_cents: number;
};

export function SellerDashboardPage() {
  const { user } = useAuth();
  const qc = useQueryClient();

  const { data, isLoading, error } = useQuery({
    queryKey: ["seller-dashboard"],
    queryFn: async () => {
      const { data } = await api.get<Dashboard>("/seller/dashboard");
      return data;
    },
    enabled: user?.role === "SELLER" && user.status === "ACTIVE",
  });

  if (!user || user.role !== "SELLER") return <Navigate to="/login" replace />;

  if (user.status === "PENDING") {
    return (
      <div className="mx-auto max-w-2xl px-4 py-16 text-center">
        <h1 className="font-serif text-2xl">Awaiting approval</h1>
        <p className="mt-4 text-stone-600">Your seller account is pending. An admin must approve you before you can list products.</p>
      </div>
    );
  }

  if (user.status === "SUSPENDED") {
    return (
      <div className="mx-auto max-w-2xl px-4 py-16 text-center">
        <h1 className="font-serif text-2xl text-red-800">Account suspended</h1>
        <p className="mt-4 text-stone-600">Your listings are hidden from buyers.</p>
      </div>
    );
  }

  if (isLoading) return <p className="p-10 text-center">Loading...</p>;
  if (error || !data) return <p className="p-10 text-center text-red-600">Failed to load dashboard</p>;

  async function ship(orderId: string) {
    await api.post(`/orders/${orderId}/ship`);
    qc.invalidateQueries({ queryKey: ["seller-dashboard"] });
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <h1 className="font-serif text-3xl">{data.store_name}</h1>
      <p className="mt-2 text-stone-600">{data.bio}</p>
      <p className="mt-4 text-lg font-medium text-teal-900">Total earnings: {formatPrice(data.total_earnings_cents)}</p>

      <section className="mt-10">
        <h2 className="font-serif text-xl">Orders to fulfill</h2>
        {data.orders.length === 0 ? (
          <p className="mt-4 text-stone-500">No orders yet.</p>
        ) : (
          <table className="mt-4 w-full text-left text-sm">
            <thead>
              <tr className="border-b text-stone-500">
                <th className="py-2">Product</th><th>Buyer</th><th>Qty</th><th>Earnings</th><th>Status</th><th></th>
              </tr>
            </thead>
            <tbody>
              {data.orders.map((o) => (
                <tr key={o.id} className="border-b">
                  <td className="py-3">{o.product_title}</td>
                  <td>{o.buyer_email}</td>
                  <td>{o.qty}</td>
                  <td>{formatPrice(o.seller_payout_cents)}</td>
                  <td>{o.order_status}</td>
                  <td>
                    {o.order_status === "PAID" && (
                      <button type="button" onClick={() => ship(o.order_id)} className="rounded-full bg-teal-800 px-3 py-1 text-xs text-white">
                        Mark shipped
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="mt-10">
        <h2 className="font-serif text-xl">My listings ({data.products.length})</h2>
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {data.products.map((p) => (
            <div key={p.id} className="rounded-xl border bg-white p-4">
              <h3 className="font-medium">{p.title}</h3>
              <p className="text-sm text-stone-500">{formatPrice(p.priceCents)} · {p.stockQty} stock · {p.status}</p>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
