import { createApi, fetchBaseQuery } from "@reduxjs/toolkit/query/react";
import { createSlice, PayloadAction } from "@reduxjs/toolkit";

export interface AuthState {
  access_token: string | null;
  refresh_token: string | null;
}

const initialState: AuthState = {
  access_token: null,
  refresh_token: null,
};

interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
  scope: string;
}

interface DeviceAuthResponse {
  device_code: string;
  user_code: string;
  verification_uri: string;
  verification_uri_complete?: string;
  expires_in: number;
  interval: number;
  code_verifier: string;
}

interface PollTokenRequest {
  device_code: string;
  code_verifier: string;
}

export const authApi = createApi({
  reducerPath: "authApi",
  baseQuery: fetchBaseQuery(),
  endpoints: (builder) => ({
    initiateDeviceAuth: builder.mutation<DeviceAuthResponse, void>({
      query: () => ({
        url: "/login",
        method: "POST",
      }),
    }),
    pollDeviceToken: builder.mutation<TokenResponse, PollTokenRequest>({
      query: (body) => ({
        url: "/login/poll",
        method: "POST",
        body,
      }),
    }),
    refreshToken: builder.mutation<TokenResponse, { refresh_token: string }>({
      query: (body) => ({
        url: "/login/refresh",
        method: "POST",
        body,
      }),
    }),
  }),
});

const authSlice = createSlice({
  name: "auth",
  initialState: initialState,
  reducers: {
    invalidateToken(state) {
      state.access_token = null;
      state.refresh_token = null;
    },
    hydrateAuth(state, action: PayloadAction<AuthState>) {
      state.access_token = action.payload.access_token;
      state.refresh_token = action.payload.refresh_token;
    },
  },
  extraReducers: (builder) => {
    builder.addMatcher(
      authApi.endpoints.pollDeviceToken.matchFulfilled,
      (state, action) => {
        state.access_token = action.payload.access_token;
        state.refresh_token = action.payload.refresh_token;
      },
    );
    builder.addMatcher(
      authApi.endpoints.refreshToken.matchFulfilled,
      (state, action) => {
        state.access_token = action.payload.access_token;
        state.refresh_token = action.payload.refresh_token;
      },
    );
  },
});

export const {
  useInitiateDeviceAuthMutation,
  usePollDeviceTokenMutation,
  useRefreshTokenMutation,
} = authApi;

export const { invalidateToken, hydrateAuth } = authSlice.actions;

export default authSlice.reducer as (
  state: AuthState,
  action: PayloadAction,
) => AuthState;
