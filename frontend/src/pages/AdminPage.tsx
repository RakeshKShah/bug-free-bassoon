import { useQuery, useQueryClient } from "@tanstack/react-query";
import api from "../api/client";
import { useAuth } from "../context/AuthContext";
import { Navigate } from "react-router-dom";

type Seller = { id: string; email: string; store_name: string; status: string; product_count: number };
type AdminProduct = { id: string; title: string; category: string; price_cents: number; stock_qty: number; status: string; visible: boolean; store_name: string; seller_status: string };

export function AdminPage() {
  const { user } = useAuth();
  const qc = useQueryClient();

  const { data: sellers = [] } = useQuery({
    queryKey: ["admin-sellers"],
    queryFn: async () => (await api.get<Seller[]>("/admin/sellers")).data,
    enabled: user?.role === "ADMIN",
  });

  const { data: products = [] } = useQuery({
    queryKey: ["admin-products"],
    queryFn: async () => (await api.get<AdminProduct[]>("/admin/products")).data,
    enabled: user?.role === "ADMIN",
  });

  if (!user || user.role !== "ADMIN") return <Navigate to="/login" replace />;

  async function updateSeller(id: string, status: string) {
    await api.put(`/admin/sellers/${id}`, { status });
    qc.invalidateQueries({ queryKey: ["admin-sellers"] });
    qc.invalidateQueries({ queryKey: ["admin-products"] });
    qc.invalidateQueries({ queryKey: ["products"] });
  }

  async function removeProduct(id: string) {
    if (!confirm("Remove this listing?")) return;
    await api.delete(`/admin/products/${id}`);
    qc.invalidateQueries({ queryKey: ["admin-products"] });
    qc.invalidateQueries({ queryKey: ["products"] });
  }

  async function runPayouts() {
    const { data } = await api.post("/admin/payouts/run");
    alert(`Processed ${data.processed} payouts (${data.demoMode ? "demo" : "live"})`);
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <h1 className="font-serif text-3xl">Admin panel</h1>
      <p className="mt-2 text-stone-600">Approve sellers, moderate listings, run weekly payouts.</p>

      <button type="button" onClick={runPayouts} className="mt-6 rounded-full bg-stone-800 px-6 py-2 text-sm text-white">
        Run weekly payouts
      </button>

      <section className="mt-12">
        <h2 className="font-serif text-2xl">Sellers</h2>
        <table className="mt-4 w-full text-left text-sm">
          <thead>
            <tr className="border-b text-stone-500">
              <th className="py-2">Store</th><th>Email</th><th>Status</th><th>Products</th><th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {sellers.map((s) => (
              <tr key={s.id} className="border-b">
                <td className="py-3 font-medium">{s.store_name}</td>
                <td>{s.email}</td>
                <td><span className={`rounded-full px-2 py-0.5 text-xs ${s.status === "ACTIVE" ? "bg-green-100 text-green-800" : s.status === "SUSPENDED" ? "bg-red-100 text-red-800" : "bg-amber-100"}`}>{s.status}</span></td>
                <td>{s.product_count}</td>
                <td className="space-x-2">
                  {s.status !== "ACTIVE" && <button type="button" onClick={() => updateSeller(s.id, "ACTIVE")} className="rounded bg-green-700 px-2 py-1 text-xs text-white">Approve</button>}
                  {s.status !== "SUSPENDED" && <button type="button" onClick={() => updateSeller(s.id, "SUSPENDED")} className="rounded bg-red-700 px-2 py-1 text-xs text-white">Suspend</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className="mt-12">
        <h2 className="font-serif text-2xl">All listings</h2>
        <p className="text-sm text-stone-500">Includes hidden listings from suspended sellers (BR-04)</p>
        <table className="mt-4 w-full text-left text-sm">
          <thead>
            <tr className="border-b text-stone-500">
              <th className="py-2">Product</th><th>Seller</th><th>Seller status</th><th>Visible</th><th>Status</th><th></th>
            </tr>
          </thead>
          <tbody>
            {products.map((p) => (
              <tr key={p.id} className={`border-b ${!p.visible ? "bg-red-50/50" : ""}`}>
                <td className="py-3">{p.title}</td>
                <td>{p.store_name}</td>
                <td>{p.seller_status}</td>
                <td>{p.visible ? "Yes" : "No"}</td>
                <td>{p.status}</td>
                <td>
                  {p.status !== "REMOVED" && (
                    <button type="button" onClick={() => removeProduct(p.id)} className="rounded bg-red-700 px-2 py-1 text-xs text-white">Remove</button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}
