import { BrowserRouter, Routes, Route } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AuthProvider } from "./context/AuthContext";
import { CartProvider } from "./context/CartContext";
import { Navbar } from "./components/Navbar";
import { HomePage } from "./pages/HomePage";
import { ProductPage } from "./pages/ProductPage";
import { CartPage } from "./pages/CartPage";
import { LoginPage } from "./pages/LoginPage";
import { SellerDashboardPage } from "./pages/SellerDashboardPage";
import { AdminPage } from "./pages/AdminPage";
import { OrdersPage } from "./pages/OrdersPage";

const qc = new QueryClient();

export default function App() {
  return (
    <QueryClientProvider client={qc}>
      <AuthProvider>
        <CartProvider>
          <BrowserRouter>
            <Navbar />
            <main>
              <Routes>
                <Route path="/" element={<HomePage />} />
                <Route path="/product/:id" element={<ProductPage />} />
                <Route path="/cart" element={<CartPage />} />
                <Route path="/login" element={<LoginPage />} />
                <Route path="/orders" element={<OrdersPage />} />
                <Route path="/seller/dashboard" element={<SellerDashboardPage />} />
                <Route path="/admin" element={<AdminPage />} />
              </Routes>
            </main>
            <footer className="border-t py-8 text-center text-sm text-stone-500">
              Craft & Co. — supporting local makers · 10% platform fee
            </footer>
          </BrowserRouter>
        </CartProvider>
      </AuthProvider>
    </QueryClientProvider>
  );
}
