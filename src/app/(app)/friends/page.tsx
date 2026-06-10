import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUser } from "@/lib/auth/me";
import { FriendsClient, type FriendsData } from "./friends-client";

export const metadata = {
  title: "Friends",
};

export default async function FriendsPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/auth?mode=signin");
  // Guests are anonymous sessions — no friends for them.
  if (user.isAnonymous) redirect("/play");

  const supabase = await createClient();
  const { data } = await supabase.rpc("get_friends_data");
  const friendsData: FriendsData = (data as FriendsData) ?? {
    friends: [],
    incoming: [],
    sent: [],
    ignored: [],
  };

  return <FriendsClient data={friendsData} userId={user.id} />;
}
