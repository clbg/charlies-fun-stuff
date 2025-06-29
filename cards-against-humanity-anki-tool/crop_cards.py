from pdf2image import convert_from_path
from PIL import Image
import os

def crop_cards_from_pdf(pdf_path, output_dir):
    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Convert PDF pages to list of images
    pages = convert_from_path(pdf_path)
    
    # Process each page
    for page_num, page in enumerate(pages):
        # Get page dimensions
        width, height = page.size
        
        # Assuming 5 rows and 4 columns of cards (5x4 grid)
        # Define margins (in pixels) for top, bottom, left, right
        margin_top = 50
        margin_bottom = 160
        margin_left = 55
        margin_right = 55
        
        # Subtract total margins from width and height before dividing
        total_margin_width = margin_left + margin_right
        total_margin_height = margin_top + margin_bottom
        card_width = (width - (total_margin_width )) // 4
        card_height = (height - (total_margin_height)) // 5
        
        # Crop each card from the grid
        for row in range(5):
            for col in range(4):
                # Calculate the cropping box (left, upper, right, lower) with margins
                left = col * card_width + margin_left
                upper = row * card_height + margin_top
                right = (col + 1) * card_width + margin_left
                lower = (row + 1) * card_height + margin_top
                
                # Crop the card
                card = page.crop((left, upper, right, lower))
                
                # Save the card as a separate image
                card_num = (page_num * 20) + (row * 4) + col + 1
                card.save(os.path.join(output_dir, f'card_{card_num:03d}.png'), 'PNG')

if __name__ == "__main__":
    pdf_file = "CAH_PrintPlay2022-RegularInk-FINAL-outlined.pdf"
    output_directory = "cards_output"
    crop_cards_from_pdf(pdf_file, output_directory)
    print(f"Cards have been cropped and saved to {output_directory}")
