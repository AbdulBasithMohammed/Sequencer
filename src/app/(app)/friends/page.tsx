import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile, getCurrentUser } from "@/lib/auth/me";
import { FriendsClient, type FriendsData } from "./friends-client";

export const metadata = {
  title: "Friends — Sequencr",
};

export default async function FriendsPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/auth?mode=signin");
  const profile = await getCurrentProfile();
  if (profile?.is_guest) redirect("/play");

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
