"""
VayalConnect Backend — Tamil Nadu Location & Mandi Intelligence

Normalizes districts, mandis, and towns across Tamil Nadu for agricultural market
lookups with AGMARKNET, Uzhavar Santhai, and local cost engines.
"""

from typing import Optional, Tuple, List, Dict

# All 38 administrative districts of Tamil Nadu
TAMIL_NADU_DISTRICTS: List[str] = [
    "Ariyalur",
    "Chengalpattu",
    "Chennai",
    "Coimbatore",
    "Cuddalore",
    "Dharmapuri",
    "Dindigul",
    "Erode",
    "Kallakurichi",
    "Kanchipuram",
    "Kanyakumari",
    "Karur",
    "Krishnagiri",
    "Madurai",
    "Mayiladuthurai",
    "Nagapattinam",
    "Namakkal",
    "Nilgiris",
    "The Nilgiris",
    "Perambalur",
    "Pudukkottai",
    "Ramanathapuram",
    "Ranipet",
    "Salem",
    "Sivaganga",
    "Tenkasi",
    "Thanjavur",
    "Theni",
    "Thoothukudi",
    "Tiruchirappalli",
    "Tirunelveli",
    "Tirupathur",
    "Tirupur",
    "Tiruvallur",
    "Tiruvannamalai",
    "Tiruvarur",
    "Vellore",
    "Viluppuram",
    "Virudhunagar",
]

# Canonical district names for normalization
DISTRICT_LOOKUP: Dict[str, str] = {d.lower(): d for d in TAMIL_NADU_DISTRICTS}
# Common aliases
DISTRICT_LOOKUP["the nilgiris"] = "The Nilgiris"
DISTRICT_LOOKUP["nilgiris"] = "The Nilgiris"
DISTRICT_LOOKUP["ooty"] = "The Nilgiris"
DISTRICT_LOOKUP["trichy"] = "Tiruchirappalli"
DISTRICT_LOOKUP["tiruchirapalli"] = "Tiruchirappalli"
DISTRICT_LOOKUP["villupuram"] = "Viluppuram"
DISTRICT_LOOKUP["tuticorin"] = "Thoothukudi"
DISTRICT_LOOKUP["tiruppur"] = "Tirupur"

# Major agricultural towns and mandis mapped to their parent district
TOWN_TO_DISTRICT: Dict[str, str] = {
    # Nilgiris
    "ooty": "The Nilgiris",
    "udhagamandalam": "The Nilgiris",
    "coonoor": "The Nilgiris",
    "kotagiri": "The Nilgiris",
    "gudalur": "The Nilgiris",

    # Coimbatore
    "mettupalayam": "Coimbatore",
    "pollachi": "Coimbatore",
    "sulur": "Coimbatore",
    "annur": "Coimbatore",
    "kinathukadavu": "Coimbatore",
    "valparai": "Coimbatore",
    "coimbatore": "Coimbatore",

    # Erode
    "perundurai": "Erode",
    "gobichettipalayam": "Erode",
    "gobi": "Erode",
    "bhavani": "Erode",
    "sathyamangalam": "Erode",
    "anthiyur": "Erode",
    "kodumudi": "Erode",
    "erode": "Erode",

    # Dindigul
    "oddanchatram": "Dindigul",
    "ottanchatram": "Dindigul",
    "palani": "Dindigul",
    "kodaikanal": "Dindigul",
    "natham": "Dindigul",
    "vedasandur": "Dindigul",
    "dindigul": "Dindigul",

    # Dharmapuri
    "pennagaram": "Dharmapuri",
    "harur": "Dharmapuri",
    "palacode": "Dharmapuri",
    "pappireddipatti": "Dharmapuri",
    "dharmapuri": "Dharmapuri",

    # Krishnagiri
    "hosur": "Krishnagiri",
    "denkanikottai": "Krishnagiri",
    "pochampalli": "Krishnagiri",
    "uthangarai": "Krishnagiri",
    "krishnagiri": "Krishnagiri",

    # Salem
    "attur": "Salem",
    "mettur": "Salem",
    "omalur": "Salem",
    "edappadi": "Salem",
    "sankari": "Salem",
    "salem": "Salem",

    # Namakkal
    "tiruchengode": "Namakkal",
    "rasipuram": "Namakkal",
    "paramathi": "Namakkal",
    "velur": "Namakkal",
    "kolli hills": "Namakkal",
    "namakkal": "Namakkal",

    # Madurai
    "melur": "Madurai",
    "usilampatti": "Madurai",
    "vadipatti": "Madurai",
    "thirumangalam": "Madurai",
    "madurai": "Madurai",

    # Theni
    "periyakulam": "Theni",
    "bodi": "Theni",
    "bodinayakanur": "Theni",
    "cumbum": "Theni",
    "uthamapalayam": "Theni",
    "theni": "Theni",

    # Tiruchirappalli
    "manapparai": "Tiruchirappalli",
    "srirangam": "Tiruchirappalli",
    "thuraiyur": "Tiruchirappalli",
    "musiri": "Tiruchirappalli",
    "lalgudi": "Tiruchirappalli",
    "trichy": "Tiruchirappalli",
    "tiruchirappalli": "Tiruchirappalli",

    # Thanjavur
    "kumbakonam": "Thanjavur",
    "pattukkottai": "Thanjavur",
    "thiruvaiyaru": "Thanjavur",
    "orathanadu": "Thanjavur",
    "thanjavur": "Thanjavur",

    # Tirunelveli & Tenkasi
    "ambasamudram": "Tirunelveli",
    "radhapuram": "Tirunelveli",
    "nanguneri": "Tirunelveli",
    "tirunelveli": "Tirunelveli",
    "tenkasi": "Tenkasi",
    "sankarankovil": "Tenkasi",
    "kadayanallur": "Tenkasi",

    # Cuddalore
    "panruti": "Cuddalore",
    "chidambaram": "Cuddalore",
    "vriddhachalam": "Cuddalore",
    "neyveli": "Cuddalore",
    "cuddalore": "Cuddalore",

    # Viluppuram & Kallakurichi
    "tindivanam": "Viluppuram",
    "gingee": "Viluppuram",
    "villupuram": "Viluppuram",
    "kallakurichi": "Kallakurichi",
    "ulundurpet": "Kallakurichi",

    # Tirupur
    "dharapuram": "Tirupur",
    "kangeyam": "Tirupur",
    "udumalaipettai": "Tirupur",
    "avinashi": "Tirupur",
    "palladam": "Tirupur",
    "tirupur": "Tirupur",

    # Vellore, Ranipet, Tirupathur
    "gudiyatham": "Vellore",
    "katpadi": "Vellore",
    "vellore": "Vellore",
    "arakkonam": "Ranipet",
    "walajah": "Ranipet",
    "ranipet": "Ranipet",
    "vaniyambadi": "Tirupathur",
    "ambur": "Tirupathur",
    "tirupathur": "Tirupathur",

    # Virudhunagar
    "rajapalayam": "Virudhunagar",
    "sivakasi": "Virudhunagar",
    "srivilliputhur": "Virudhunagar",
    "aruppukottai": "Virudhunagar",
    "sattur": "Virudhunagar",
    "virudhunagar": "Virudhunagar",

    # Karur
    "kulithalai": "Karur",
    "aravakurichi": "Karur",
    "karur": "Karur",

    # Pudukkottai
    "aranthangi": "Pudukkottai",
    "alangudi": "Pudukkottai",
    "pudukkottai": "Pudukkottai",

    # Sivaganga
    "karaikudi": "Sivaganga",
    "devakottai": "Sivaganga",
    "manamadurai": "Sivaganga",
    "sivaganga": "Sivaganga",

    # Ramanathapuram
    "paramakudi": "Ramanathapuram",
    "rameshwaram": "Ramanathapuram",
    "ramanathapuram": "Ramanathapuram",

    # Thoothukudi
    "kovilpatti": "Thoothukudi",
    "tiruchendur": "Thoothukudi",
    "thoothukudi": "Thoothukudi",

    # Kanyakumari
    "nagercoil": "Kanyakumari",
    "padmanabhapuram": "Kanyakumari",
    "kanyakumari": "Kanyakumari",

    # Kanchipuram & Chengalpattu
    "kanchipuram": "Kanchipuram",
    "sriperumbudur": "Kanchipuram",
    "chengalpattu": "Chengalpattu",
    "tambaram": "Chengalpattu",
    "maduranthakam": "Chengalpattu",

    # Tiruvallur
    "tiruvallur": "Tiruvallur",
    "ponneri": "Tiruvallur",
    "gummidipoondi": "Tiruvallur",
    "avadi": "Tiruvallur",

    # Tiruvannamalai
    "cheyyar": "Tiruvannamalai",
    "arani": "Tiruvannamalai",
    "polur": "Tiruvannamalai",
    "tiruvannamalai": "Tiruvannamalai",

    # Ariyalur & Perambalur
    "ariyalur": "Ariyalur",
    "jayankondam": "Ariyalur",
    "perambalur": "Perambalur",

    # Nagapattinam, Mayiladuthurai, Tiruvarur
    "mayiladuthurai": "Mayiladuthurai",
    "sirkazhi": "Mayiladuthurai",
    "nagapattinam": "Nagapattinam",
    "velankanni": "Nagapattinam",
    "tiruvarur": "Tiruvarur",
    "mannargudi": "Tiruvarur",

    # Chennai
    "chennai": "Chennai",
    "koyambedu": "Chennai",
}


def resolve_tn_location(location: Optional[str]) -> Tuple[Optional[str], Optional[str], bool]:
    """
    Given a user-provided location string (district, city, town, or mandi),
    resolves: (district_name, market_name, is_valid_tamilnadu).

    Examples:
      "Ooty" -> ("The Nilgiris", "Ooty", True)
      "Mettupalayam, Coimbatore, Tamil Nadu" -> ("Coimbatore", "Mettupalayam", True)
      "Madurai" -> ("Madurai", "Madurai", True)
      "Tamil Nadu" -> ("Tamil Nadu", None, True)
      "London" -> (None, None, False)
    """
    if not location or not location.strip():
        return None, None, False

    clean = location.strip()
    clean_lower = clean.lower()

    if clean_lower in ("tamil nadu", "tamilnadu", "tn"):
        return "Tamil Nadu", None, True

    # Check comma-separated tokens (e.g. "Mettupalayam, Coimbatore, Tamil Nadu")
    tokens = [t.strip() for t in clean.split(",") if t.strip()]

    # First pass: check each token against town mapping or district lookup
    identified_district = None
    identified_market = None

    for token in tokens:
        tl = token.lower()
        if tl in ("tamil nadu", "tamilnadu", "india"):
            continue
        if tl in TOWN_TO_DISTRICT:
            identified_district = TOWN_TO_DISTRICT[tl]
            identified_market = token
            break
        if tl in DISTRICT_LOOKUP:
            identified_district = DISTRICT_LOOKUP[tl]
            identified_market = token
            break

    if identified_district:
        return identified_district, identified_market or clean, True

    # Substring search across keys
    for town_key, dist_val in TOWN_TO_DISTRICT.items():
        if town_key in clean_lower or clean_lower in town_key:
            return dist_val, clean, True

    for dist_key, dist_val in DISTRICT_LOOKUP.items():
        if dist_key in clean_lower or clean_lower in dist_key:
            return dist_val, clean, True

    return None, None, False


def is_valid_tn_location(location: Optional[str]) -> bool:
    """Check if location string represents a recognizable Tamil Nadu location."""
    _, _, is_valid = resolve_tn_location(location)
    return is_valid
