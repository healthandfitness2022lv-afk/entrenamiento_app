import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool isRegister = false;

  Future<void> _submit() async {
    if (isRegister && nameController.text.trim().isEmpty) {
      _showError("Ingresa tu nombre");
      return;
    }

    setState(() => isLoading = true);

    try {
      UserCredential cred;

      if (isRegister) {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        final user = cred.user;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'name': nameController.text.trim(),
            'email': user.email,
            'role': 'athlete',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Error de autenticación");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ======================
                    // 🧠 HEADER
                    // ======================
                    Icon(
                      Icons.fitness_center,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isRegister ? "Crear cuenta" : "Bienvenido",
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isRegister
                          ? "Regístrate para comenzar"
                          : "Inicia sesión para continuar",
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey),
                    ),

                    const SizedBox(height: 24),

                    // ======================
                    // ✍️ FORM
                    // ======================
                    if (isRegister)
                      _inputField(
                        controller: nameController,
                        label: "Nombre",
                        icon: Icons.person_outline,
                      ),

                    _inputField(
                      controller: emailController,
                      label: "Email",
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),

                    _inputField(
                      controller: passwordController,
                      label: "Contraseña",
                      icon: Icons.lock_outline,
                      obscure: true,
                    ),

                    const SizedBox(height: 24),

                    // ======================
                    // 🔘 BOTÓN PRINCIPAL
                    // ======================
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isRegister ? "Registrarse" : "Ingresar",
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ======================
                    // 🔁 TOGGLE
                    // ======================
                    TextButton(
                      onPressed: () {
                        setState(() {
                          isRegister = !isRegister;
                          nameController.clear();
                        });
                      },
                      child: Text(
                        isRegister
                            ? "¿Ya tienes cuenta? Inicia sesión"
                            : "¿No tienes cuenta? Regístrate",
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
