import axios from "axios";

const API_URL = import.meta.env.VITE_API_URL ?? "";

const api = axios.create({
  baseURL: API_URL ? API_URL.replace(/\/$/, "") : "/api",
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

export default api;

export function formatPrice(cents: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100);
}

export type Product = {
  id: string;
  title: string;
  description?: string;
  category: string;
  price_cents: number;
  stock_qty: number;
  photos: string[];
  status: "active" | "sold_out" | "removed";
  store_name?: string;
  reviews?: { id: string; rating: number; body: string; created_at: string }[];
};

export type User = {
  id: string;
  email: string;
  role: "BUYER" | "SELLER" | "ADMIN";
  status: "PENDING" | "ACTIVE" | "SUSPENDED";
  sellerProfile?: { id: string; storeName: string; bio: string };
};
