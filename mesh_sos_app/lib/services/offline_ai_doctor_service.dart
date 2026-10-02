class TriageGuidance {
  final String title;
  final String category;
  final String severity; // CRITICAL, URGENT, MODERATE
  final List<String> immediateActions;
  final List<String> warnings;
  final String loraSummary; // Compact 1-line summary for LoRa broadcast

  const TriageGuidance({
    required this.title,
    required this.category,
    required this.severity,
    required this.immediateActions,
    required this.warnings,
    required this.loraSummary,
  });
}

class OfflineAiDoctorService {
  static final OfflineAiDoctorService instance = OfflineAiDoctorService._internal();
  OfflineAiDoctorService._internal();

  final List<TriageGuidance> _protocols = const [
    TriageGuidance(
      title: 'Arterial / Severe Bleeding',
      category: 'Trauma & Hemorrhage',
      severity: 'CRITICAL',
      immediateActions: [
        '1. Apply direct, firm, continuous pressure with a clean cloth or bandage.',
        '2. If on an extremity and direct pressure fails, apply a Tourniquet 2–3 inches ABOVE the wound (never over a joint).',
        '3. Tighten tourniquet until bright red bleeding completely stops.',
        '4. Note the exact time the tourniquet was applied.',
        '5. Keep patient warm and lying flat to prevent hemorrhagic shock.',
      ],
      warnings: [
        'DO NOT loosen or remove a tourniquet once applied; only qualified surgeons should release it.',
        'DO NOT probe or remove embedded foreign objects from the wound.',
      ],
      loraSummary: 'TRIAGE-RED: Severe Arterial Bleeding, Tourniquet Applied, Risk of Shock',
    ),
    TriageGuidance(
      title: 'Unconscious Victim & CPR Protocol',
      category: 'Cardiac & Respiration',
      severity: 'CRITICAL',
      immediateActions: [
        '1. Check responsiveness: Tap shoulders firmly and shout loudly.',
        '2. Check breathing: Look for chest rise for 5–10 seconds.',
        '3. If no breathing or gasping, begin Chest Compressions immediately.',
        '4. Rate: 100–120 compressions per minute (push hard and fast in center of chest, 2 inches deep).',
        '5. Ratio: 30 compressions followed by 2 rescue breaths (or continuous Hands-Only CPR).',
        '6. Continue CPR until emergency rescue arrives or patient breathes.',
      ],
      warnings: [
        'Do not interrupt compressions for more than 10 seconds.',
        'Ensure the victim is lying on a firm, flat surface.',
      ],
      loraSummary: 'TRIAGE-RED: Victim Unconscious, CPR in Progress, Immediate ALS Needed',
    ),
    TriageGuidance(
      title: 'Earthquake / Rubble Entrapment',
      category: 'Search & Rescue',
      severity: 'CRITICAL',
      immediateActions: [
        '1. Cover your mouth and nose with cloth to avoid inhaling toxic dust.',
        '2. Tap metal pipes or structural beams in groups of 3 (Rescue Signal) instead of screaming to conserve oxygen.',
        '3. If limbs are compressed by heavy debris >15 mins, monitor for Crush Syndrome (release can cause sudden potassium rush).',
        '4. Protect airway and maintain clear respiratory path.',
        '5. Activate LoRa Mesh Beacon and keep phone display low power.',
      ],
      warnings: [
        'Do not light matches or lighters due to possible ruptured gas lines.',
        'Avoid unnecessary movement that could shift unstable debris piles.',
      ],
      loraSummary: 'TRIAGE-RED: Structural Rubble Entrapment, Airway at Risk, Extrication Needed',
    ),
    TriageGuidance(
      title: 'Snake / Venomous Bite',
      category: 'Toxicology & Bites',
      severity: 'URGENT',
      immediateActions: [
        '1. Keep victim calm and completely still. Immobilize the bitten limb BELOW heart level.',
        '2. Remove rings, watches, and tight clothing before swelling starts.',
        '3. Apply a firm pressure immobilization bandage from fingers/toes upwards.',
        '4. Mark the edge of swelling on skin with a pen and record the timestamp.',
        '5. Prepare for rapid evacuation to hospital with Anti-Snake Venom (ASV).',
      ],
      warnings: [
        'NEVER cut the bite wound, suck venom, or apply electrical shock.',
        'DO NOT apply ice packs or tight arterial tourniquets for snakebites.',
      ],
      loraSummary: 'TRIAGE-YELLOW: Venomous Snakebite, Limb Immobilized, Anti-Venom Required',
    ),
    TriageGuidance(
      title: 'Compound / Open Bone Fracture',
      category: 'Orthopedic Trauma',
      severity: 'URGENT',
      immediateActions: [
        '1. Control any active bleeding by applying pressure around (not on) the bone.',
        '2. Cover the protruding bone with a sterile or clean moist dressing.',
        '3. Immobilize the joint above and below the fracture using an improvised splint (wood, cardboard, sticks).',
        '4. Check pulse and capillary refill in fingers/toes past the fracture.',
        '5. Keep the victim warm and resting still.',
      ],
      warnings: [
        'DO NOT attempt to push protruding bone back inside the skin.',
        'DO NOT attempt to straighten a severely deformed limb.',
      ],
      loraSummary: 'TRIAGE-YELLOW: Open Bone Fracture, Splinted, Sterile Dressing Applied',
    ),
    TriageGuidance(
      title: 'Severe Burns & Chemical Exposure',
      category: 'Burns & Thermal Trauma',
      severity: 'URGENT',
      immediateActions: [
        '1. Cool the burn immediately under gentle, cool running water for 10–20 minutes.',
        '2. Cover with a clean, dry, non-adherent sterile cloth or plastic wrap.',
        '3. Keep the patient warm (burn victims rapidly lose body temperature).',
        '4. If chemical burn, flush with copious water for at least 20 minutes.',
        '5. Elevate burned extremities above heart level to minimize edema.',
      ],
      warnings: [
        'DO NOT apply ice, butter, oil, toothpaste, or ointments to raw burns.',
        'DO NOT burst blisters or peel off charred clothing stuck to skin.',
      ],
      loraSummary: 'TRIAGE-YELLOW: Severe Burn Injury, Cooled & Dressed, High Infection Risk',
    ),
    TriageGuidance(
      title: 'Hypothermia & Severe Cold Exposure',
      category: 'Environmental Hazard',
      severity: 'MODERATE',
      immediateActions: [
        '1. Move victim out of the wind and cold; remove wet clothing immediately.',
        '2. Insulate body from frozen ground using sleeping pads, foliage, or packs.',
        '3. Apply warm dry compresses to core areas: chest, neck, and groin.',
        '4. If conscious, give warm, sweet non-caffeinated liquids.',
        '5. Wrap in reflective emergency thermal space blanket.',
      ],
      warnings: [
        'DO NOT rub frostbitten skin or use direct hot water/stoves (causes tissue necrosis).',
        'DO NOT give alcohol (dilates vessels and accelerates core heat loss).',
      ],
      loraSummary: 'TRIAGE-GREEN: Hypothermia/Exposure, Passive Rewarming Active, Sheltered',
    ),
    TriageGuidance(
      title: 'Emergency Water Disinfection',
      category: 'Wilderness Survival',
      severity: 'MODERATE',
      immediateActions: [
        '1. Filter cloudy water through clean cloth, sand, or charcoal to remove sediment.',
        '2. Bring water to a rolling boil for at least 1 full minute (3 mins at altitude >2000m).',
        '3. If boiling is impossible, add 2 drops of unscented liquid bleach per liter (wait 30 mins).',
        '4. Alternatively, use chlorine dioxide or iodine purification tablets per packet instructions.',
        '5. Store in sealed, disinfected containers.',
      ],
      warnings: [
        'Boiling kills bacteria/viruses but does NOT remove chemical poisons or heavy metals.',
        'Avoid stagnant water sources near chemical runoff or industrial sites.',
      ],
      loraSummary: 'INFO: Water Disinfection Guide, Boiling/Chlorine Protocol Completed',
    ),
  ];

  List<TriageGuidance> getAllProtocols() => _protocols;

  /// Fast offline natural-language matching across emergency terms
  List<TriageGuidance> search(String query) {
    if (query.trim().isEmpty) return _protocols;
    final clean = query.toLowerCase();

    final matches = _protocols.where((p) {
      return p.title.toLowerCase().contains(clean) ||
          p.category.toLowerCase().contains(clean) ||
          p.immediateActions.any((a) => a.toLowerCase().contains(clean)) ||
          p.warnings.any((w) => w.toLowerCase().contains(clean));
    }).toList();

    if (matches.isEmpty) {
      // Fallback keyword scoring
      if (clean.contains('blood') || clean.contains('bleed') || clean.contains('cut')) {
        return _protocols.where((p) => p.title.contains('Bleeding')).toList();
      }
      if (clean.contains('cpr') || clean.contains('heart') || clean.contains('breath') || clean.contains('unconscious')) {
        return _protocols.where((p) => p.title.contains('CPR')).toList();
      }
      if (clean.contains('snake') || clean.contains('poison') || clean.contains('bite')) {
        return _protocols.where((p) => p.title.contains('Snake')).toList();
      }
      if (clean.contains('bone') || clean.contains('broken') || clean.contains('fracture')) {
        return _protocols.where((p) => p.title.contains('Fracture')).toList();
      }
      if (clean.contains('burn') || clean.contains('fire') || clean.contains('chemical')) {
        return _protocols.where((p) => p.title.contains('Burns')).toList();
      }
      if (clean.contains('water') || clean.contains('drink') || clean.contains('purify')) {
        return _protocols.where((p) => p.title.contains('Water')).toList();
      }
      if (clean.contains('earthquake') || clean.contains('rubble') || clean.contains('trapped')) {
        return _protocols.where((p) => p.title.contains('Rubble')).toList();
      }
    }

    return matches.isNotEmpty ? matches : _protocols;
  }
}
