import os
import time
import sqlite3
import hashlib
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from google import genai
from google.genai import types

app = Flask(__name__)
CORS(app)

# CONFIGURATION
UPLOAD_FOLDER = 'static/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# INITIALIZE GOOGLE AI CLIENT with Gemini 3
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', 'AIzaSyCHEVuBlEt9-06oh05RdvZfbWbJklvE4xA')
client = genai.Client(api_key=GEMINI_API_KEY, http_options={'api_version': 'v1alpha'})

# Cache TTL (24 hours)
CACHE_TTL = 24 * 60 * 60

# DATABASE SETUP
def init_db():
    conn = sqlite3.connect('users.db')
    c = conn.cursor()
    
    # Users table
    c.execute('''CREATE TABLE IF NOT EXISTS users 
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                  email TEXT UNIQUE, 
                  password TEXT, 
                  trials INTEGER DEFAULT 5, 
                  advice_credits INTEGER DEFAULT 0,
                  analysis_credits INTEGER DEFAULT 0,
                  tier TEXT DEFAULT 'free',
                  savings_goal REAL DEFAULT 1000.0,
                  current_savings REAL DEFAULT 0.0,
                  daily_tips_enabled INTEGER DEFAULT 1)''')
    
    # Expenses table
    c.execute('''CREATE TABLE IF NOT EXISTS expenses
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  user_id INTEGER,
                  category TEXT,
                  amount REAL,
                  date TEXT,
                  notes TEXT,
                  FOREIGN KEY(user_id) REFERENCES users(id))''')
    
    # Goals table
    c.execute('''CREATE TABLE IF NOT EXISTS goals
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  user_id INTEGER,
                  title TEXT,
                  target_amount REAL,
                  current_amount REAL,
                  deadline TEXT,
                  category TEXT,
                  FOREIGN KEY(user_id) REFERENCES users(id))''')
    
    # AI Response Cache table
    c.execute('''CREATE TABLE IF NOT EXISTS ai_cache
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  query_hash TEXT UNIQUE,
                  query_text TEXT,
                  response_text TEXT,
                  model_used TEXT,
                  created_at TEXT,
                  expires_at TEXT)''')
    
    conn.commit()
    conn.close()

init_db()

# === HELPER FUNCTIONS ===

def get_cache_key(query_text, model='gemini-3-flash-preview'):
    """Generate a cache key from query text and model"""
    combined = f"{model}:{query_text.lower().strip()}"
    return hashlib.sha256(combined.encode()).hexdigest()

def get_cached_response(query_text, model='gemini-3-flash-preview'):
    """Retrieve cached AI response if available and not expired"""
    try:
        conn = sqlite3.connect('users.db')
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        query_hash = get_cache_key(query_text, model)
        now = datetime.utcnow().isoformat()
        
        result = c.execute(
            "SELECT response_text FROM ai_cache WHERE query_hash = ? AND expires_at > ?",
            (query_hash, now)
        ).fetchone()
        
        conn.close()
        
        if result:
            return result['response_text']
        return None
    except Exception as e:
        print(f"Cache retrieval error: {e}")
        return None

def cache_response(query_text, response_text, model='gemini-3-flash-preview'):
    """Cache an AI response"""
    try:
        conn = sqlite3.connect('users.db')
        c = conn.cursor()
        
        query_hash = get_cache_key(query_text, model)
        created_at = datetime.utcnow().isoformat()
        expires_at = (datetime.utcnow() + timedelta(seconds=CACHE_TTL)).isoformat()
        
        c.execute(
            '''INSERT OR REPLACE INTO ai_cache 
               (query_hash, query_text, response_text, model_used, created_at, expires_at)
               VALUES (?, ?, ?, ?, ?, ?)''',
            (query_hash, query_text, response_text, model, created_at, expires_at)
        )
        
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Cache storage error: {e}")

def call_gemini_with_search(prompt, use_search=True, thinking_level='medium'):
    """
    Call Gemini 3 Flash with Google Search grounding and caching
    """
    # Check cache first
    cached = get_cached_response(prompt)
    if cached:
        return cached
    
    try:
        tools = []
        if use_search:
            tools.append({"google_search": {}})
        
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=prompt,
            config=types.GenerateContentConfig(
                tools=tools if tools else None,
                thinking_config=types.ThinkingConfig(thinking_level=thinking_level)
            )
        )
        
        response_text = response.text
        
        # Cache the response
        cache_response(prompt, response_text)
        
        return response_text
    except Exception as e:
        return f"AI Error: {str(e)}"

# === AUTH ROUTES ===

@app.route('/auth/register', methods=['POST'])
def register():
    data = request.json
    email = data.get('email')
    password = generate_password_hash(data.get('password'))
    
    try:
        conn = sqlite3.connect('users.db')
        c = conn.cursor()
        c.execute("INSERT INTO users (email, password) VALUES (?, ?)", (email, password))
        user_id = c.lastrowid
        conn.commit()
        
        user_data = {
            'user_id': str(user_id),
            'email': email,
            'trials_remaining': 5,
            'advice_credits_remaining': 0,
            'analysis_credits_remaining': 0,
            'tier': 'free',
            'savings_goal': 1000.0,
            'current_savings': 0.0,
            'daily_tips_enabled': True
        }
        
        conn.close()
        return jsonify({'success': True, 'message': 'User registered', 'user': user_data})
    except:
        return jsonify({'success': False, 'message': 'User already exists'}), 400

@app.route('/auth/login', methods=['POST'])
def login():
    data = request.json
    conn = sqlite3.connect('users.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE email = ?", (data.get('email'),)).fetchone()
    
    if user and check_password_hash(user['password'], data.get('password')):
        return jsonify({
            'success': True, 
            'user': {
                'user_id': str(user['id']), 
                'email': user['email'], 
                'trials_remaining': user['trials'],
                'advice_credits_remaining': user['advice_credits'],
                'analysis_credits_remaining': user['analysis_credits'],
                'tier': user['tier'],
                'savings_goal': user['savings_goal'],
                'current_savings': user['current_savings'],
                'daily_tips_enabled': bool(user['daily_tips_enabled'])
            }
        })
    return jsonify({'success': False, 'message': 'Invalid credentials'}), 401

@app.route('/auth/google', methods=['POST'])
def google_auth():
    # Simplified Google auth - in production, verify the token
    data = request.json
    email = f"google_user_{int(time.time())}@gmail.com"  # Mock email
    
    try:
        conn = sqlite3.connect('users.db')
        c = conn.cursor()
        c.execute("INSERT INTO users (email, password) VALUES (?, ?)", 
                 (email, generate_password_hash('google_oauth')))
        user_id = c.lastrowid
        conn.commit()
        
        user_data = {
            'user_id': str(user_id),
            'email': email,
            'trials_remaining': 5,
            'advice_credits_remaining': 0,
            'analysis_credits_remaining': 0,
            'tier': 'free',
            'savings_goal': 1000.0,
            'current_savings': 0.0,
            'daily_tips_enabled': True
        }
        
        conn.close()
        return jsonify({'success': True, 'user': user_data})
    except:
        return jsonify({'success': False, 'message': 'Google auth failed'}), 400

@app.route('/auth/forgot-password', methods=['POST'])
def forgot_password():
    # In production, send actual password reset email
    return jsonify({
        'success': True,
        'message': 'Password reset link sent to your email'
    })

# === FINANCIAL AI ROUTES ===

@app.route('/financial/advice', methods=['POST'])
def get_financial_advice():
    """
    General financial advice using Gemini 3 Flash with Google Search
    """
    data = request.json
    user_id = data.get('user_id')
    query = data.get('query')
    
    if not query:
        return jsonify({'success': False, 'message': 'Query required'}), 400
    
    # Enhanced prompt for financial advice
    enhanced_prompt = f"""You are a friendly financial advisor for busy mums seeking financial independence. 
Provide practical, actionable advice that's easy to understand and implement.

User Question: {query}

Please provide:
1. Direct answer to their question
2. Practical tips they can implement today
3. Any relevant money-saving strategies
4. If applicable, mention risks to be aware of

Keep responses concise, warm, and encouraging. Focus on empowering financial independence."""

    try:
        advice = call_gemini_with_search(
            enhanced_prompt,
            use_search=True,
            thinking_level='medium'
        )
        
        return jsonify({
            'success': True,
            'advice': advice
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/financial/shopping-alternatives', methods=['POST'])
def get_shopping_alternatives():
    """
    Find cheaper shopping alternatives using Gemini 3 with Google Search
    """
    data = request.form
    user_id = data.get('user_id')
    product = data.get('product', '')
    
    # Handle image if provided
    image_context = ""
    if 'image' in request.files:
        image_file = request.files['image']
        # In production, analyze image with Gemini Vision
        image_context = "(User uploaded product image)"
    
    prompt = f"""As a money-saving expert, help find cheaper alternatives for this product:

Product: {product}
{image_context}

Please provide:
1. 3-5 cheaper alternatives from different stores
2. Estimated price for each alternative
3. Potential savings compared to premium brands
4. Quality considerations (if the cheaper option is worth it)

Format as a list with store names, product names, and prices.
Use current market data from Australia/UK/US (whichever is most relevant)."""

    try:
        response_text = call_gemini_with_search(
            prompt,
            use_search=True,
            thinking_level='medium'
        )
        
        # Parse response into structured format
        # This is a simplified parser - in production, use structured outputs
        alternatives = [
            {
                'product': 'Budget Alternative 1',
                'store': 'Aldi',
                'price': '3.99',
                'savings': '2.00'
            },
            {
                'product': 'Budget Alternative 2',
                'store': 'Lidl',
                'price': '4.50',
                'savings': '1.49'
            },
            {
                'product': 'Store Brand',
                'store': 'Tesco',
                'price': '4.25',
                'savings': '1.74'
            }
        ]
        
        return jsonify({
            'success': True,
            'alternatives': alternatives,
            'ai_advice': response_text
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/financial/batch-cooking', methods=['POST'])
def get_batch_cooking_costs():
    """
    Calculate batch cooking costs with Gemini 3 Flash
    """
    data = request.json
    user_id = data.get('user_id')
    meals = data.get('meals', [])
    servings = data.get('servings', 4)
    
    meals_str = ", ".join(meals)
    
    prompt = f"""As a budget cooking expert, analyze the cost of batch cooking these meals:

Meals: {meals_str}
Servings per meal: {servings}

Please provide:
1. Estimated total cost for all meals
2. Cost per serving for each meal
3. Cost breakdown by meal
4. Money-saving tips for bulk buying ingredients
5. Comparison with buying ready-made meals or takeout

Use current UK/US supermarket prices. Be specific with costs."""

    try:
        analysis_text = call_gemini_with_search(
            prompt,
            use_search=True,
            thinking_level='medium'
        )
        
        # Mock structured response - in production, parse the AI response
        analysis = {
            'total_cost': '45.50',
            'per_serving': '2.84',
            'meals': [
                {
                    'name': meal,
                    'cost': f'{15.50 + i * 2:.2f}',
                    'per_serving': f'{(15.50 + i * 2) / servings:.2f}'
                }
                for i, meal in enumerate(meals)
            ],
            'ai_advice': analysis_text
        }
        
        return jsonify({
            'success': True,
            'analysis': analysis
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/financial/renovation', methods=['POST'])
def get_renovation_advice():
    """
    Renovation savings advice using Gemini 3 Flash with Search
    """
    data = request.json
    user_id = data.get('user_id')
    project_type = data.get('project_type')
    budget = data.get('budget')
    
    prompt = f"""As a home renovation expert focused on budget savings, provide advice for:

Project: {project_type} renovation
Budget: ${budget}

Please provide:
1. DIY opportunities to save money (with difficulty ratings)
2. Cost-effective material alternatives
3. When to hire professionals vs DIY
4. Estimated cost breakdown (materials vs labor)
5. Potential total savings by following your advice
6. Timeline considerations

Be specific and practical. Focus on maximizing value within budget."""

    try:
        advice_text = call_gemini_with_search(
            prompt,
            use_search=True,
            thinking_level='high'  # High thinking for complex renovation planning
        )
        
        # Mock structured response
        advice = {
            'diy_tips': [
                'Painting walls yourself can save £500-800',
                'Install fixtures and fittings (save £200-400)',
                'Remove old materials/demolition (save £300-600)'
            ],
            'material_tips': [
                'Use laminate instead of hardwood (save 40-60%)',
                'Choose mid-range tiles instead of premium (save £15-25/sqm)',
                'Shop clearance sections for discounted materials'
            ],
            'comparison': [
                'Full professional job: £8,000-12,000',
                'Hybrid DIY approach: £4,000-6,000',
                'Your potential savings: £4,000-6,000'
            ],
            'estimated_savings': '4500',
            'ai_advice': advice_text
        }
        
        return jsonify({
            'success': True,
            'advice': advice
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/financial/investment', methods=['POST'])
def get_investment_guidance():
    """
    Investment guidance for beginners using Gemini 3 Flash
    """
    data = request.json
    user_id = data.get('user_id')
    amount = data.get('amount')
    risk_tolerance = data.get('risk_tolerance', 'Moderate')
    
    prompt = f"""As a beginner-friendly financial advisor, provide investment guidance for:

Amount to invest: ${amount}
Risk tolerance: {risk_tolerance}

Please provide:
1. Recommended asset allocation (percentages for different investment types)
2. Specific investment options suitable for beginners (ETFs, index funds, etc.)
3. Risk considerations for this risk level
4. Expected returns (realistic estimates)
5. Next steps to get started
6. Common mistakes to avoid

Keep language simple and encouraging. This is for someone new to investing.
Use current investment data and focus on long-term wealth building."""

    try:
        guidance_text = call_gemini_with_search(
            prompt,
            use_search=True,
            thinking_level='high'  # High thinking for investment planning
        )
        
        # Mock structured response
        guidance = {
            'allocation': [
                '60% Stock market index funds (long-term growth)',
                '30% Bonds (stability and income)',
                '10% Cash/emergency fund (liquidity)'
            ],
            'options': [
                'Vanguard FTSE Global All Cap Index Fund',
                'Premium Bonds (UK) - safe, tax-free',
                'S&P 500 Index Fund (US stocks)',
                'Government bonds for stability'
            ],
            'risks': [
                'Market volatility - your investment may go down as well as up',
                'Inflation risk - ensure returns beat inflation',
                'Time horizon - invest for at least 5 years'
            ],
            'next_steps': 'Open a stocks & shares ISA, start with a small amount monthly, research recommended funds, set up automatic contributions.',
            'ai_advice': guidance_text
        }
        
        return jsonify({
            'success': True,
            'guidance': guidance
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/financial/compare', methods=['POST'])
def compare_costs():
    """
    General cost comparison tool
    """
    data = request.json
    user_id = data.get('user_id')
    comparison_type = data.get('type')  # e.g., 'products', 'services', 'subscriptions'
    items = data.get('items', [])
    
    items_str = ", ".join(items)
    
    prompt = f"""Compare the costs and value of these {comparison_type}:

Items: {items_str}

Please provide:
1. Current prices for each
2. Value for money analysis
3. Which offers best value and why
4. Any hidden costs to consider
5. Your recommendation

Use current market data and be specific with numbers."""

    try:
        comparison_text = call_gemini_with_search(
            prompt,
            use_search=True,
            thinking_level='medium'
        )
        
        return jsonify({
            'success': True,
            'comparison': comparison_text
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/financial/daily-tip', methods=['GET'])
def get_daily_tip():
    """
    Generate a daily money-saving tip
    """
    user_id = request.args.get('user_id')
    
    # Use date as part of cache key for daily tips
    today = datetime.utcnow().strftime('%Y-%m-%d')
    cache_key = f"daily_tip_{today}"
    
    # Try to get cached tip for today
    try:
        conn = sqlite3.connect('users.db')
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        result = c.execute(
            "SELECT response_text FROM ai_cache WHERE query_hash = ?",
            (hashlib.sha256(cache_key.encode()).hexdigest(),)
        ).fetchone()
        
        if result:
            conn.close()
            return jsonify({
                'success': True,
                'tip': result['response_text']
            })
    except:
        pass
    
    prompt = """Generate a single practical money-saving tip for busy mums. 
The tip should be:
- Immediately actionable
- Specific and practical
- Focused on everyday life (shopping, cooking, household, or investing basics)
- Encouraging and empowering
- 2-3 sentences maximum

Examples:
- "Switch to store-brand products for items like pasta, rice, and canned goods. You'll save 30-50% without sacrificing quality."
- "Batch cook on Sundays and freeze portions. You'll save money on takeaways and reduce food waste by 40%."
- "Cancel unused subscriptions today. The average household wastes £50/month on forgotten subscriptions."

Generate one unique tip different from these examples."""

    try:
        tip = call_gemini_with_search(
            prompt,
            use_search=False,  # Don't need search for general tips
            thinking_level='low'  # Low thinking for simple tips
        )
        
        # Cache this tip for the day
        cache_response(cache_key, tip)
        
        return jsonify({
            'success': True,
            'tip': tip
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

# === USER DATA ROUTES ===

@app.route('/user/<user_id>/expenses', methods=['GET', 'POST'])
def handle_expenses(user_id):
    conn = sqlite3.connect('users.db')
    
    if request.method == 'POST':
        data = request.json
        c = conn.cursor()
        c.execute(
            '''INSERT INTO expenses (user_id, category, amount, date, notes)
               VALUES (?, ?, ?, ?, ?)''',
            (user_id, data['category'], data['amount'], data['date'], data.get('notes', ''))
        )
        conn.commit()
        conn.close()
        return jsonify({'success': True})
    
    else:  # GET
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        expenses = c.execute(
            'SELECT * FROM expenses WHERE user_id = ? ORDER BY date DESC LIMIT 50',
            (user_id,)
        ).fetchall()
        conn.close()
        
        return jsonify({
            'expenses': [
                {
                    'id': str(e['id']),
                    'category': e['category'],
                    'amount': e['amount'],
                    'date': e['date'],
                    'notes': e['notes']
                }
                for e in expenses
            ]
        })

@app.route('/user/<user_id>/goals', methods=['GET', 'POST'])
def handle_goals(user_id):
    conn = sqlite3.connect('users.db')
    
    if request.method == 'POST':
        data = request.json
        c = conn.cursor()
        c.execute(
            '''INSERT INTO goals (user_id, title, target_amount, current_amount, deadline, category)
               VALUES (?, ?, ?, ?, ?, ?)''',
            (user_id, data['title'], data['target_amount'], data.get('current_amount', 0),
             data['deadline'], data['category'])
        )
        conn.commit()
        conn.close()
        return jsonify({'success': True})
    
    else:  # GET
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        goals = c.execute(
            'SELECT * FROM goals WHERE user_id = ? ORDER BY deadline',
            (user_id,)
        ).fetchall()
        conn.close()
        
        return jsonify({
            'goals': [
                {
                    'id': str(g['id']),
                    'title': g['title'],
                    'target_amount': g['target_amount'],
                    'current_amount': g['current_amount'],
                    'deadline': g['deadline'],
                    'category': g['category']
                }
                for g in goals
            ]
        })

@app.route('/user/<user_id>/profile', methods=['GET'])
def get_user_profile(user_id):
    conn = sqlite3.connect('users.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    conn.close()
    
    if user:
        return jsonify({
            'user_id': str(user['id']),
            'email': user['email'],
            'tier': user['tier'],
            'trials_remaining': user['trials'],
            'savings_goal': user['savings_goal'],
            'current_savings': user['current_savings']
        })
    return jsonify({'error': 'User not found'}), 404

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)