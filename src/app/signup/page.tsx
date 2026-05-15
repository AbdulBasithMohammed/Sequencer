import { redirect } from "next/navigation";

export default function SignupRedirect() {
  redirect("/auth?mode=signup");
}
