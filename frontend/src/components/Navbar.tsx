import { Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export function Navbar() {
  const { user, logout } = useAuth();

  return (
    <header className="sticky top-0 z-50 border-b border-stone-200 bg-white/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
        <Link to="/" className="font-serif text-2xl font-semibold text-teal-900">
          Craft & Co.
        </Link>
        <nav className="flex flex-wrap items-center gap-4 text-sm font-medium">
          <Link to="/" className="hover:text-teal-800">Browse</Link>
          <Link to="/cart" className="hover:text-teal-800">Cart</Link>
          {user?.role === "SELLER" && (
            <Link to="/seller/dashboard" className="hover:text-teal-800">Seller Dashboard</Link>
          )}
          {user?.role === "ADMIN" && (
            <Link to="/admin" className="hover:text-teal-800">Admin</Link>
          )}
          {user ? (
            <>
              <span className="text-stone-500">{user.email}</span>
              <button type="button" onClick={logout} className="text-teal-800 hover:underline">
                Sign out
              </button>
            </>
          ) : (
            <Link to="/login" className="rounded-full bg-teal-800 px-4 py-2 text-white hover:bg-teal-900">
              Sign in
            </Link>
          )}
        </nav>
      </div>
    </header>
  );
}
