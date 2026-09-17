import { combineReducers, configureStore } from "@reduxjs/toolkit";
import chatSlice, { chatApi, ChatState } from "./services/chat";
import { useDispatch, useSelector } from "react-redux";
import authSlice, { authApi, AuthState } from "./services/auth";

// Save auth state to localStorage
const saveAuthState = (state: AuthState) => {
  try {
    if (typeof window === "undefined") return;
    const serializedState = JSON.stringify(state);
    localStorage.setItem("auth", serializedState);
  } catch (err) {
    console.error("Failed to save auth state:", err);
  }
};

const rootReducer = combineReducers({
  chat: chatSlice,
  [chatApi.reducerPath]: chatApi.reducer,
  auth: authSlice,
  [authApi.reducerPath]: authApi.reducer,
});

export const store = configureStore({
  reducer: rootReducer,
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware()
      .concat(chatApi.middleware)
      .concat(authApi.middleware),
});

// Subscribe to store changes and save auth state
store.subscribe(() => {
  saveAuthState(store.getState().auth);
});

export interface RootState {
  chat: ChatState;
  auth: AuthState;
}

export const useAppSelector = useSelector.withTypes<RootState>();
export const useAppDispatch = useDispatch.withTypes<typeof store.dispatch>();
