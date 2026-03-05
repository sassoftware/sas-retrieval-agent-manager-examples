"use client";
import { store } from "@/store";
import { hydrateAuth } from "@/services/auth";
import { Provider } from "react-redux";
import { useEffect, useRef } from "react";

export default function StoreWrapper({
  children,
}: {
  children: React.ReactNode;
}) {
  const hydrated = useRef(false);

  useEffect(() => {
    if (!hydrated.current) {
      hydrated.current = true;
      // Load auth state from localStorage
      try {
        const serializedState = localStorage.getItem("auth");
        if (serializedState) {
          const authState = JSON.parse(serializedState);
          store.dispatch(hydrateAuth(authState));
        }
      } catch (err) {
        console.error("Failed to hydrate auth state:", err);
      }
    }
  }, []);

  return <Provider store={store}>{children}</Provider>;
}
