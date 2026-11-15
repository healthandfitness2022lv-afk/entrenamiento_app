import '../services/rpe_factor_service.dart';

double rpeFactor(double rpe) {
  return RpeFactorService().getFactor(rpe);
}
