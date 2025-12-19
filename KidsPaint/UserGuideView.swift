//
//  UserGuideView.swift
//  KidsPaint by Fivethirty Softworks
//
//  Created by Cornelius on 12/18/25.
//


import SwiftUI

struct UserGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                Text("KidsPaint – User Guide")
                    .font(.largeTitle.weight(.bold))
                    .padding(.bottom, 8)

                section("Getting Started") {
                    text("KidsPaint is a simple drawing app for kids. There are no documents to manage — just draw and save your artwork as an image.")
                }

                section("Tools") {
                    bullet("Brush – draw freely on the canvas")
                    bullet("Eraser – erase parts of your drawing")
                    bullet("Stickers – place and edit fun stickers")
                    bullet("Move – pan and zoom the canvas")
                }

                section("Colors & Size") {
                    bullet("Pick colors using the color circles at the bottom")
                    bullet("Use the size slider to change brush or sticker size")
                    text("Changing colors only affects new drawings or stickers.")
                }

                section("Stickers") {
                    bullet("Choose a sticker from the sticker strip")
                    bullet("Click on the canvas to place it")
                    bullet("Drag to move the sticker")
                    bullet("Use the square handle to resize")
                    bullet("Use the round handle to rotate")
                    bullet("Press Delete to remove a selected sticker")
                }

                section("Background Images") {
                    bullet("Use “Open Image” to draw on top of a photo")
                    bullet("Remove it anytime from the More (•••) menu")
                }

                section("Saving") {
                    bullet("Click “Save PNG” to export your artwork")
                    bullet("Saved files are standard image files")
                }

                section("Clearing the Canvas") {
                    text("Use the Trash button to clear everything. You’ll be asked to confirm to prevent accidents.")
                }

                section("Tips for Parents") {
                    bullet("KidsPaint never changes existing artwork accidentally")
                    bullet("There is no wrong way to use the app")
                    bullet("Stickers are intentionally large and easy to grab")
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 600)
    }

    // MARK: - Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.body)
    }

    private func text(_ text: String) -> some View {
        Text(text)
            .font(.body)
    }
}
