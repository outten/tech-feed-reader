import SwiftUI

struct SignInView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var recoveryCode = ""
    @State private var showingSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Tech Feed Reader")
                        .font(.largeTitle.bold())
                    Text("Log in with a recovery code from your account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    TextField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $recoveryCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .padding(.horizontal)

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await auth.logIn(recoveryCode: recoveryCode) }
                    } label: {
                        if auth.isBusy {
                            ProgressView()
                        } else {
                            Text("Log In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(recoveryCode.trimmingCharacters(in: .whitespaces).isEmpty || auth.isBusy)
                    .padding(.horizontal)
                }

                Spacer()

                Button("New here? Sign up") {
                    showingSignUp = true
                }
                .padding(.bottom)
            }
            .sheet(isPresented: $showingSignUp) {
                SafariSignUpView(url: AppConfig.signUpURL)
            }
        }
    }
}
