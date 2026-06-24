import { createContext, useContext, useState, type ReactNode } from "react";

export type CartItem = { product_id: string; title: string; price_cents: number; qty: number; photo?: string };

type CartContextType = {
  items: CartItem[];
  add: (item: Omit<CartItem, "qty">, qty?: number) => void;
  remove: (productId: string) => void;
  updateQty: (productId: string, qty: number) => void;
  clear: () => void;
  totalCents: number;
};

const CartContext = createContext<CartContextType | null>(null);

export function CartProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<CartItem[]>(() => {
    try {
      return JSON.parse(localStorage.getItem("cart") ?? "[]");
    } catch {
      return [];
    }
  });

  function persist(next: CartItem[]) {
    setItems(next);
    localStorage.setItem("cart", JSON.stringify(next));
  }

  function add(item: Omit<CartItem, "qty">, qty = 1) {
    const existing = items.find((i) => i.product_id === item.product_id);
    if (existing) {
      persist(items.map((i) => (i.product_id === item.product_id ? { ...i, qty: i.qty + qty } : i)));
    } else {
      persist([...items, { ...item, qty }]);
    }
  }

  function remove(productId: string) {
    persist(items.filter((i) => i.product_id !== productId));
  }

  function updateQty(productId: string, qty: number) {
    if (qty <= 0) return remove(productId);
    persist(items.map((i) => (i.product_id === productId ? { ...i, qty } : i)));
  }

  function clear() {
    persist([]);
  }

  const totalCents = items.reduce((s, i) => s + i.price_cents * i.qty, 0);

  return (
    <CartContext.Provider value={{ items, add, remove, updateQty, clear, totalCents }}>
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const ctx = useContext(CartContext);
  if (!ctx) throw new Error("useCart must be used within CartProvider");
  return ctx;
}
