import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export function LoginPage() {
  const { login, register } = useAuth();
  const navigate = useNavigate();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState<"BUYER" | "SELLER">("BUYER");
  const [storeName, setStoreName] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      if (mode === "login") {
        await login(email, password);
      } else {
        await register({ email, password, role, storeName: role === "SELLER" ? storeName : undefined });
      }
      navigate("/");
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error;
      setError(msg ?? "Authentication failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="mx-auto max-w-md px-4 py-16">
      <h1 className="text-center font-serif text-3xl">{mode === "login" ? "Sign in" : "Join Craft & Co."}</h1>
      <div className="mt-6 flex gap-2 rounded-lg bg-stone-100 p-1">
        <button type="button" onClick={() => setMode("login")} className={`flex-1 rounded-md py-2 text-sm ${mode === "login" ? "bg-white shadow" : ""}`}>Sign in</button>
        <button type="button" onClick={() => setMode("register")} className={`flex-1 rounded-md py-2 text-sm ${mode === "register" ? "bg-white shadow" : ""}`}>Register</button>
      </div>
      <form onSubmit={handleSubmit} className="mt-8 space-y-4">
        {mode === "register" && (
          <div className="flex gap-2">
            {(["BUYER", "SELLER"] as const).map((r) => (
              <button key={r} type="button" onClick={() => setRole(r)} className={`flex-1 rounded-md py-2 text-sm ${role === r ? "bg-teal-800 text-white" : "bg-stone-100"}`}>
                {r === "BUYER" ? "Buyer" : "Seller"}
              </button>
            ))}
          </div>
        )}
        <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Email" className="w-full rounded-lg border px-4 py-3" />
        <input type="password" required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Password" className="w-full rounded-lg border px-4 py-3" />
        {mode === "register" && role === "SELLER" && (
          <input type="text" required value={storeName} onChange={(e) => setStoreName(e.target.value)} placeholder="Store name" className="w-full rounded-lg border px-4 py-3" />
        )}
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button type="submit" disabled={loading} className="w-full rounded-full bg-teal-800 py-3 text-white disabled:opacity-50">
          {loading ? "..." : mode === "login" ? "Sign in" : "Create account"}
        </button>
      </form>
      <p className="mt-6 text-center text-xs text-stone-500">
        Demo: buyer@craftco.com / Buyer1234! · seller@craftco.com / Seller1234!
      </p>
    </div>
  );
}
