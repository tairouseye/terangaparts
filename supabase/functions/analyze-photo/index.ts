// =====================================================================
// Edge Function : analyze-photo — lecture de photos par l'IA (Claude)
//
//   kind = "vin"  : carte grise / plaque constructeur -> VIN, marque,
//                   modele, annee, motorisation
//   kind = "part" : photo d'une piece -> nom, categorie, reference OEM
//
// Securite :
//   - appel reserve a un utilisateur connecte (session client OU invitee),
//     verifie via le jeton Supabase transmis par l'app ;
//   - quota par utilisateur sur 24 h (table photo_analyses, service_role) ;
//   - la cle Anthropic reste cote serveur (secret ANTHROPIC_API_KEY).
// =====================================================================
import Anthropic from "npm:@anthropic-ai/sdk@1.10.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@1.10.0/helpers/zod";
import { z } from "npm:zod@4.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.119.2";

const MODEL = "claude-opus-5-5";
const DAILY_LIMIT = 30; // analyses par utilisateur et par 24 h
const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // 5 Mo apres decodage base64
const MEDIA_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"] as const;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

// --------------------------- Schemas de sortie ---------------------------
const VinResult = z.object({
  vin: z.string().nullable(),
  brand: z.string().nullable(),
  model: z.string().nullable(),
  year: z.number().int().nullable(),
  engine: z.string().nullable(),
  confidence: z.enum(["high", "medium", "low"]),
  note: z.string().nullable(),
});

const PartResult = z.object({
  is_auto_part: z.boolean(),
  category: z.string().nullable(),
  part_name: z.string().nullable(),
  catalog_match: z.string().nullable(),
  oem_part_number: z.string().nullable(),
  side_or_position: z.string().nullable(),
  confidence: z.enum(["high", "medium", "low"]),
  note: z.string().nullable(),
});

const VIN_PROMPT = `Tu lis la photo d'un document ou d'une plaque de vehicule envoyee par un client au Senegal : carte grise senegalaise (certificat d'immatriculation, en francais), plaque constructeur, ou VIN frappe sur le chassis ou visible sous le pare-brise.

Extrais :
- vin : le numero d'identification (VIN), 17 caracteres, sans espaces. Sur la carte grise senegalaise il figure souvent comme « N° de châssis » ou « N° de série » (rubrique E). Les lettres I, O et Q n'existent pas dans un VIN : lis-les comme 1, 0 et 0. Si tu ne lis pas les 17 caracteres avec certitude, renvoie null plutot que de deviner.
- brand : la marque (ex. Hyundai, Kia, Genesis, SsangYong / KGM, Chevrolet / Daewoo, Renault Samsung), d'apres le document ou d'apres le prefixe du VIN (KMH = Hyundai, KNA/KNB/KNC/KND/KNE = Kia, KPT = SsangYong, KL = GM Korea, KNM = Renault Samsung).
- model : le modele commercial (ex. Tucson, Sportage), seulement s'il est ecrit ou certain.
- year : l'annee du modele ou de premiere mise en circulation, seulement si elle est lisible ou certaine.
- engine : la motorisation ou cylindree si elle est indiquee (ex. 2.0 CRDi, G4KD).
- confidence : ta confiance globale dans le VIN.
- note : une phrase courte en francais pour le client si la photo est floue, coupee ou ne montre pas de VIN ; sinon null.

N'invente jamais une valeur : null quand elle n'est pas lisible.`;

function partPrompt(catalog: Record<string, string[]>) {
  return `Tu identifies une piece automobile sur la photo envoyee par un client (vehicules coreens : Hyundai, Kia, Genesis, SsangYong...).

Catalogue de l'application (categorie -> pieces) :
${JSON.stringify(catalog)}

Renvoie :
- is_auto_part : false si la photo ne montre pas une piece automobile.
- category : une des categories du catalogue ci-dessus, recopiee a l'identique (sinon "Autre").
- catalog_match : le nom EXACT d'une piece de cette categorie si elle correspond, sinon null.
- part_name : le nom de la piece en francais, court et precis (ex. « Plaquettes de frein avant »).
- oem_part_number : la reference constructeur si elle est lisible sur la piece ou l'etiquette (format Hyundai/Kia du type 58101-2SA70), sinon null. Ne devine pas.
- side_or_position : gauche/droite, avant/arriere si c'est visible, sinon null.
- confidence : ta confiance dans l'identification.
- note : une phrase courte en francais pour le client si la photo ne suffit pas (ex. demander une photo de l'etiquette), sinon null.`;
}

const VIN_RE = /^[A-HJ-NPR-Z0-9]{17}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // ---- 1. Utilisateur connecte (client ou invite) ----
  const authHeader = req.headers.get("Authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json({ error: "unauthorized" }, 401);

  // ---- 2. Requete ----
  let body: {
    kind?: string;
    image_base64?: string;
    media_type?: string;
    catalog?: Record<string, string[]>;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const kind = body.kind === "vin" || body.kind === "part" ? body.kind : null;
  const mediaType = MEDIA_TYPES.find((m) => m === body.media_type);
  const data = (body.image_base64 ?? "").replace(/\s/g, "");
  if (!kind || !mediaType || !data) return json({ error: "bad_request" }, 400);
  if ((data.length * 3) / 4 > MAX_IMAGE_BYTES) {
    return json({ error: "image_too_large" }, 413);
  }
  const catalog =
    kind === "part" && body.catalog && JSON.stringify(body.catalog).length < 8000
      ? body.catalog
      : {};

  // ---- 3. Quota 24 h ----
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await admin
    .from("photo_analyses")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", since);
  if ((count ?? 0) >= DAILY_LIMIT) return json({ error: "quota_exceeded" }, 429);
  const { data: logRow } = await admin
    .from("photo_analyses")
    .insert({ user_id: user.id, kind })
    .select("id")
    .single();

  // ---- 4. Analyse par Claude ----
  const anthropic = new Anthropic(); // lit ANTHROPIC_API_KEY
  const image: Anthropic.ImageBlockParam = {
    type: "image",
    source: { type: "base64", media_type: mediaType, data },
  };
  try {
    const params = {
      model: MODEL,
      max_tokens: 4000,
      output_config: { effort: "low" as const },
    };
    let result: unknown;
    if (kind === "vin") {
      const res = await anthropic.messages.parse({
        ...params,
        output_config: { ...params.output_config, format: zodOutputFormat(VinResult) },
        messages: [{ role: "user", content: [image, { type: "text", text: VIN_PROMPT }] }],
      });
      if (res.stop_reason === "refusal" || !res.parsed_output) {
        return json({ error: "unreadable" }, 422);
      }
      const r = res.parsed_output;
      // Garde-fou : un VIN mal forme n'est pas propose au client.
      const vin = r.vin?.toUpperCase().replace(/[^A-Z0-9]/g, "") ?? null;
      result = { ...r, vin: vin && VIN_RE.test(vin) ? vin : null };
    } else {
      const res = await anthropic.messages.parse({
        ...params,
        output_config: { ...params.output_config, format: zodOutputFormat(PartResult) },
        messages: [
          { role: "user", content: [image, { type: "text", text: partPrompt(catalog) }] },
        ],
      });
      if (res.stop_reason === "refusal" || !res.parsed_output) {
        return json({ error: "unreadable" }, 422);
      }
      result = res.parsed_output;
    }
    if (logRow) await admin.from("photo_analyses").update({ ok: true }).eq("id", logRow.id);
    return json({ kind, result });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json({ error: "busy" }, 503);
    if (error instanceof Anthropic.AuthenticationError) {
      console.error("ANTHROPIC_API_KEY invalide ou absente");
      return json({ error: "not_configured" }, 503);
    }
    if (error instanceof Anthropic.APIError) {
      console.error(`Claude API ${error.status}: ${error.message}`);
      return json({ error: "analysis_failed" }, 502);
    }
    console.error(error);
    return json({ error: "analysis_failed" }, 500);
  }
});
