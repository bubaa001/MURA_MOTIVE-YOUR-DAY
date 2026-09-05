import { useState } from "react";
import { login, registerEmployee } from "./api";

export default function Login({ onLoggedIn }: { onLoggedIn: () => void }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [registering, setRegistering] = useState(false);
  const [email, setEmail] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (registering) {
        await registerEmployee(username, email, password);
      } else {
        await login(username, password);
      }
      onLoggedIn();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={submit}>
        <h1>TheFeeder</h1>
        <p className="muted">{registering ? "Create an employee account" : "Staff sign-in for book extraction &amp; review"}</p>
        <input
          placeholder="Username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          autoFocus
        />
        <input
          type="password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        {registering && (
          <>
            <input
              type="email"
              placeholder="Work email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </>
        )}
        {error && <div className="error">{error}</div>}
        <button disabled={busy || !username || !password || (registering && !email)}>
          {busy ? "Please wait…" : registering ? "Create employee account" : "Sign in"}
        </button>
        <button className="primary" type="button" onClick={() => setRegistering(!registering)} disabled={busy}>
          {registering ? "Back to sign in" : "Sign up as employee"}
        </button>
      </form>
    </div>
  );
}
