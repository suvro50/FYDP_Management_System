-- Insert Pre-FYDP sample data into live database
-- Get user IDs
SET @suvrojit = (SELECT user_id FROM users WHERE university_id='PFYDP001');
SET @zainab  = (SELECT user_id FROM users WHERE university_id='PFYDP002');
SET @hamza   = (SELECT user_id FROM users WHERE university_id='PFYDP003');
SET @nusrat  = (SELECT user_id FROM users WHERE university_id='PFYDP004');
SET @rafiq   = (SELECT user_id FROM users WHERE university_id='PFYDP005');
SET @samira  = (SELECT user_id FROM users WHERE university_id='PFYDP006');

-- Profiles
INSERT INTO pre_fydp_profiles (user_id, bio, cgpa, skills, domain_interests, preferred_role, github_url, linkedin_url, target_trimester, availability_status, profile_strength) VALUES
(@suvrojit, 'Full-stack developer passionate about AI and ML projects.', 3.65, '["Python","React","Node.js","MySQL","TensorFlow"]', '["AI","ML","Software Engineering"]', 'Full-stack Developer', 'https://github.com/suvrojit', 'https://linkedin.com/in/suvrojit-bose', 'Spring 2026', 'LOOKING', 71),
(@zainab, 'Frontend specialist with design skills.', 3.52, '["React","Vue.js","Figma","UI/UX","CSS"]', '["Software Engineering","Mobile Application"]', 'Frontend Developer', 'https://github.com/zainabali', 'https://linkedin.com/in/zainab-ali', 'Spring 2026', 'IN_TEAM', 85),
(@hamza, 'Backend developer with cloud and DevOps experience.', 3.78, '["Java","Spring Boot","Docker","AWS","PostgreSQL"]', '["Software Engineering","Cloud Computing"]', 'Backend Developer', 'https://github.com/hamzaiqbal', 'https://linkedin.com/in/hamza-iqbal', 'Spring 2026', 'IN_TEAM', 90),
(@nusrat, 'ML researcher interested in NLP and computer vision.', 3.88, '["Python","TensorFlow","PyTorch","NLP","OpenCV"]', '["AI","NLP","Data Analytics"]', 'ML Engineer', 'https://github.com/nusratjahan', NULL, 'Spring 2026', 'LOOKING', 60),
(@rafiq, 'Cybersecurity enthusiast with CTF experience.', 3.45, '["Python","Kali Linux","Wireshark","Networking"]', '["Cybersecurity","IoT"]', 'Security Analyst', NULL, NULL, 'Spring 2026', 'LOOKING', 40),
(@samira, 'IoT and embedded systems developer.', 3.30, '["C++","Arduino","Raspberry Pi","MQTT","Python"]', '["IoT","Hardware"]', 'Embedded Developer', NULL, NULL, 'Spring 2026', 'LOOKING', 35);

-- Groups
INSERT INTO pre_fydp_groups (group_name, domain, description, required_skills, max_members, github_url, created_by, group_status) VALUES
('NeuralVerse', 'AI', 'Building an AI-powered virtual study assistant using GPT models and RAG.', '["Python","TensorFlow","React","NLP"]', 5, 'https://github.com/neuralverse', @zainab, 'OPEN'),
('CyberShield', 'Cybersecurity', 'AI-driven intrusion detection system for university networks.', '["Python","MySQL","Backend","Networking"]', 5, NULL, @rafiq, 'OPEN'),
('MediCare AI', 'ML', 'Predictive diagnostics using federated learning.', '["Python","TensorFlow","Frontend"]', 4, NULL, @nusrat, 'OPEN'),
('CloudForge', 'Software Engineering', 'Containerized micro-services platform for student startups.', '["Backend","Node.js","MySQL","Docker"]', 5, 'https://github.com/cloudforge', @hamza, 'OPEN'),
('DataPulse', 'Data Analytics', 'Real-time analytics dashboard for e-commerce platforms.', '["Python","React","MongoDB","D3.js"]', 4, NULL, @samira, 'OPEN'),
('SmartCampus', 'IoT', 'IoT-based smart campus management system with sensors.', '["C++","Arduino","React","MQTT"]', 5, NULL, @samira, 'FULL');

-- Group Members
INSERT INTO pre_fydp_group_members (group_id, user_id, member_role) VALUES
(1, @zainab, 'Lead'), (1, @suvrojit, 'Backend'), (1, @nusrat, 'ML Engineer'), (1, @samira, 'Hardware'),
(3, @nusrat, 'Lead'), (3, @suvrojit, 'Frontend'),
(4, @hamza, 'Lead'), (4, @zainab, 'Frontend'), (4, @rafiq, 'Security'),
(6, @samira, 'Lead'), (6, @suvrojit, 'Backend'), (6, @zainab, 'Frontend'), (6, @hamza, 'DevOps'), (6, @nusrat, 'Tester');

-- Join Requests
INSERT INTO pre_fydp_join_requests (group_id, sender_id, request_type, message, request_status) VALUES
(2, @suvrojit, 'JOIN_REQUEST', 'I have experience with Python and networking!', 'PENDING'),
(5, @suvrojit, 'JOIN_REQUEST', 'Interested in data analytics!', 'PENDING'),
(1, @rafiq, 'JOIN_REQUEST', 'Can I join your AI project?', 'PENDING'),
(4, @suvrojit, 'JOIN_REQUEST', 'Full-stack developer here!', 'ACCEPTED'),
(3, @samira, 'JOIN_REQUEST', 'IoT background, interested in health tech', 'REJECTED');
