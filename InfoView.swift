//
//  InfpView.swift
//  neu
//
//  Created by its on 16.03.25.
//

import SwiftUI

struct InfoView: View {
    var body: some View {
        VStack {
            Image(systemName: "graduationcap.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .padding()
                        
                        Image("Hochschule_Koblenz.svg")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                        
                        Text("Projekt zur Hämoglobinoxygenierung")
                            .font(.title)
                            .padding()
                        
                        Text("Hochschule: Hochschule Koblenz")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        Text("Betreuer: Prof. Dr. André Steimers")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        Text("Studentin: Nora Laouar")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        Spacer()
                    }
                    .padding()
                }
            }

