/// Parametres de planification du module de voyage, persistes dans la
/// base trip_planner (table parametres, cle/valeur). Regroupent les
/// reglages qui influencent le calcul des trajets et l'affichage des
/// durees.
class ParametresPlanification {
  /// Vitesse moyenne de marche en km/h utilisee pour corriger la duree
  /// estimee par le profil piestier OSRM (qui suppose ~5 km/h sur
  /// terrain plat). En montagne, les baroudeurs descendent souvent sous
  /// 4 km/h : la duree affichee doit refléter cette realite.
  final double vitesseMarcheKmh;

  /// Vitesse moyenne a velo en km/h. Le profil FOSSGIS suppose un velo
  /// de ville ; un cyclotouriste charge descend plutot vers 15-18 km/h.
  final double vitesseVeloKmh;

  /// Si vrai, les itineraires voiture evitent les autoroutes et les
  /// routes a peage dans la mesure du possible (option exclude= d'OSRM).
  final bool eviterAutoroutes;

  /// Si vrai, les itineraires voiture evitent les segments a peage
  /// (exclude=toll).
  final bool eviterPeages;

  ParametresPlanification({
    this.vitesseMarcheKmh = 4.5,
    this.vitesseVeloKmh = 18.0,
    this.eviterAutoroutes = false,
    this.eviterPeages = false,
  });

  ParametresPlanification copyWith({
    double? vitesseMarcheKmh,
    double? vitesseVeloKmh,
    bool? eviterAutoroutes,
    bool? eviterPeages,
  }) {
    return ParametresPlanification(
      vitesseMarcheKmh: vitesseMarcheKmh ?? this.vitesseMarcheKmh,
      vitesseVeloKmh: vitesseVeloKmh ?? this.vitesseVeloKmh,
      eviterAutoroutes: eviterAutoroutes ?? this.eviterAutoroutes,
      eviterPeages: eviterPeages ?? this.eviterPeages,
    );
  }

  Map<String, String> toMap() => {
        'vitesse_marche_kmh': vitesseMarcheKmh.toString(),
        'vitesse_velo_kmh': vitesseVeloKmh.toString(),
        'eviter_autoroutes': eviterAutoroutes ? '1' : '0',
        'eviter_peages': eviterPeages ? '1' : '0',
      };

  factory ParametresPlanification.fromMap(Map<String, String?> map) {
    double parseDouble(String? v, double def) =>
        v == null ? def : double.tryParse(v) ?? def;
    bool parseBool(String? v, bool def) {
      if (v == null) return def;
      return v == '1' || v.toLowerCase() == 'true';
    }

    return ParametresPlanification(
      vitesseMarcheKmh: parseDouble(map['vitesse_marche_kmh'], 4.5),
      vitesseVeloKmh: parseDouble(map['vitesse_velo_kmh'], 18.0),
      eviterAutoroutes: parseBool(map['eviter_autoroutes'], false),
      eviterPeages: parseBool(map['eviter_peages'], false),
    );
  }
}
