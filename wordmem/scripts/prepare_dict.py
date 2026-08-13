#!/usr/bin/env python3
"""
Generate ecdict_mini.db from ECDICT CSV data.
Creates a SQLite database with FTS5 virtual table and indexes.

Usage:
    python scripts/prepare_dict.py --input <csv_path> --output <db_path>

If the CSV is small, this script also adds common English words to ensure
a minimum usable dictionary.
"""

import csv
import sqlite3
import os
import sys
import argparse

# Common English words to ensure minimum dictionary coverage
COMMON_WORDS = [
    ("the", "/ðə/", "art.", "这；那"),
    ("be", "/biː/", "v.", "是；存在"),
    ("to", "/tuː/", "prep.", "到；向"),
    ("of", "/əv/", "prep.", "属于...的"),
    ("and", "/ænd/", "conj.", "和；与"),
    ("a", "/eɪ/", "art.", "一个"),
    ("in", "/ɪn/", "prep.", "在...里"),
    ("that", "/ðæt/", "pron.", "那个"),
    ("have", "/hæv/", "v.", "有；拥有"),
    ("I", "/aɪ/", "pron.", "我"),
    ("it", "/ɪt/", "pron.", "它"),
    ("for", "/fɔː/", "prep.", "为了"),
    ("not", "/nɒt/", "adv.", "不"),
    ("on", "/ɒn/", "prep.", "在...上"),
    ("with", "/wɪð/", "prep.", "和...一起"),
    ("he", "/hiː/", "pron.", "他"),
    ("as", "/æz/", "conj.", "如同"),
    ("you", "/juː/", "pron.", "你"),
    ("do", "/duː/", "v.", "做"),
    ("at", "/æt/", "prep.", "在"),
    ("this", "/ðɪs/", "pron.", "这个"),
    ("but", "/bʌt/", "conj.", "但是"),
    ("his", "/hɪz/", "pron.", "他的"),
    ("by", "/baɪ/", "prep.", "通过"),
    ("from", "/frɒm/", "prep.", "从"),
    ("they", "/ðeɪ/", "pron.", "他们"),
    ("we", "/wiː/", "pron.", "我们"),
    ("say", "/seɪ/", "v.", "说"),
    ("her", "/hɜː/", "pron.", "她的"),
    ("she", "/ʃiː/", "pron.", "她"),
    ("or", "/ɔː/", "conj.", "或者"),
    ("an", "/æn/", "art.", "一个"),
    ("will", "/wɪl/", "v.", "将要"),
    ("my", "/maɪ/", "pron.", "我的"),
    ("one", "/wʌn/", "num.", "一"),
    ("all", "/ɔːl/", "adj.", "所有的"),
    ("would", "/wʊd/", "v.", "将；愿意"),
    ("there", "/ðeə/", "adv.", "那里"),
    ("their", "/ðeə/", "pron.", "他们的"),
    ("what", "/wɒt/", "pron.", "什么"),
    ("so", "/səʊ/", "adv.", "所以"),
    ("up", "/ʌp/", "adv.", "向上"),
    ("out", "/aʊt/", "adv.", "出去"),
    ("if", "/ɪf/", "conj.", "如果"),
    ("about", "/əˈbaʊt/", "prep.", "关于"),
    ("who", "/huː/", "pron.", "谁"),
    ("get", "/ɡet/", "v.", "得到"),
    ("which", "/wɪtʃ/", "pron.", "哪个"),
    ("go", "/ɡəʊ/", "v.", "去"),
    ("me", "/miː/", "pron.", "我"),
    ("when", "/wen/", "adv.", "何时"),
    ("make", "/meɪk/", "v.", "制作"),
    ("can", "/kæn/", "v.", "能"),
    ("like", "/laɪk/", "v.", "喜欢"),
    ("time", "/taɪm/", "n.", "时间"),
    ("no", "/nəʊ/", "adv.", "不"),
    ("just", "/dʒʌst/", "adv.", "只是"),
    ("him", "/hɪm/", "pron.", "他"),
    ("know", "/nəʊ/", "v.", "知道"),
    ("take", "/teɪk/", "v.", "拿"),
    ("people", "/ˈpiːpl/", "n.", "人们"),
    ("into", "/ˈɪntuː/", "prep.", "进入"),
    ("year", "/jɪə/", "n.", "年"),
    ("your", "/jɔː/", "pron.", "你的"),
    ("good", "/ɡʊd/", "adj.", "好的"),
    ("some", "/sʌm/", "adj.", "一些"),
    ("could", "/kʊd/", "v.", "可以"),
    ("them", "/ðem/", "pron.", "他们"),
    ("see", "/siː/", "v.", "看见"),
    ("other", "/ˈʌðə/", "adj.", "其他的"),
    ("than", "/ðæn/", "conj.", "比"),
    ("then", "/ðen/", "adv.", "然后"),
    ("now", "/naʊ/", "adv.", "现在"),
    ("look", "/lʊk/", "v.", "看"),
    ("only", "/ˈəʊnli/", "adv.", "仅仅"),
    ("come", "/kʌm/", "v.", "来"),
    ("over", "/ˈəʊvə/", "prep.", "在...上方"),
    ("think", "/θɪŋk/", "v.", "想；认为"),
    ("also", "/ˈɔːlsəʊ/", "adv.", "也"),
    ("back", "/bæk/", "adv.", "回来"),
    ("after", "/ˈɑːftə/", "prep.", "在...之后"),
    ("use", "/juːz/", "v.", "使用"),
    ("two", "/tuː/", "num.", "二"),
    ("how", "/haʊ/", "adv.", "如何"),
    ("our", "/ˈaʊə/", "pron.", "我们的"),
    ("work", "/wɜːk/", "v.", "工作"),
    ("first", "/fɜːst/", "adj.", "第一"),
    ("well", "/wel/", "adv.", "好"),
    ("way", "/weɪ/", "n.", "路；方法"),
    ("even", "/ˈiːvən/", "adv.", "甚至"),
    ("new", "/njuː/", "adj.", "新的"),
    ("want", "/wɒnt/", "v.", "想要"),
    ("because", "/bɪˈkɒz/", "conj.", "因为"),
    ("any", "/ˈeni/", "adj.", "任何"),
    ("these", "/ðiːz/", "pron.", "这些"),
    ("give", "/ɡɪv/", "v.", "给"),
    ("day", "/deɪ/", "n.", "天；日"),
    ("most", "/məʊst/", "adv.", "最"),
    ("us", "/ʌs/", "pron.", "我们"),
    ("great", "/ɡreɪt/", "adj.", "伟大的"),
    ("are", "/ɑː/", "v.", "是"),
    ("long", "/lɒŋ/", "adj.", "长的"),
    ("made", "/meɪd/", "v.", "制作(past)"),
    ("found", "/faʊnd/", "v.", "找到(past)"),
    ("here", "/hɪə/", "adv.", "这里"),
    ("still", "/stɪl/", "adv.", "仍然"),
    ("man", "/mæn/", "n.", "男人"),
    ("between", "/bɪˈtwiːn/", "prep.", "在...之间"),
    ("both", "/bəʊθ/", "pron.", "两者"),
    ("little", "/ˈlɪtl/", "adj.", "小的"),
    ("own", "/əʊn/", "adj.", "自己的"),
    ("down", "/daʊn/", "adv.", "向下"),
    ("life", "/laɪf/", "n.", "生活"),
    ("right", "/raɪt/", "adj.", "正确的"),
    ("back", "/bæk/", "n.", "背面"),
    ("world", "/wɜːld/", "n.", "世界"),
    ("too", "/tuː/", "adv.", "也；太"),
    ("many", "/ˈmeni/", "adj.", "许多"),
    ("again", "/əˈɡen/", "adv.", "再次"),
    ("same", "/seɪm/", "adj.", "相同的"),
    ("another", "/əˈnʌðə/", "pron.", "另一个"),
    ("make", "/meɪk/", "v.", "制造"),
    ("word", "/wɜːd/", "n.", "单词"),
    ("begin", "/bɪˈɡɪn/", "v.", "开始"),
    ("after", "/ˈɑːftə/", "prep.", "之后"),
    ("old", "/əʊld/", "adj.", "老的"),
    ("try", "/traɪ/", "v.", "尝试"),
    ("hand", "/hænd/", "n.", "手"),
    ("high", "/haɪ/", "adj.", "高的"),
    ("different", "/ˈdɪfrənt/", "adj.", "不同的"),
    ("place", "/pleɪs/", "n.", "地方"),
    ("small", "/smɔːl/", "adj.", "小的"),
    ("large", "/lɑːdʒ/", "adj.", "大的"),
    ("next", "/nekst/", "adj.", "下一个"),
    ("early", "/ˈɜːli/", "adv.", "早"),
    ("young", "/jʌŋ/", "adj.", "年轻的"),
    ("important", "/ɪmˈpɔːtnt/", "adj.", "重要的"),
    ("few", "/fjuː/", "adj.", "少的"),
    ("public", "/ˈpʌblɪk/", "adj.", "公共的"),
    ("bad", "/bæd/", "adj.", "坏的"),
    ("same", "/seɪm/", "adj.", "同样的"),
    ("able", "/ˈeɪbl/", "adj.", "能够的"),
    ("run", "/rʌn/", "v.", "跑", ),
    ("write", "/raɪt/", "v.", "写"),
    ("read", "/riːd/", "v.", "读"),
    ("speak", "/spiːk/", "v.", "说"),
    ("listen", "/ˈlɪsn/", "v.", "听"),
    ("learn", "/lɜːn/", "v.", "学习"),
    ("understand", "/ˌʌndəˈstænd/", "v.", "理解"),
    ("remember", "/rɪˈmembə/", "v.", "记得"),
    ("forget", "/fəˈɡet/", "v.", "忘记"),
    ("love", "/lʌv/", "v.", "爱"),
    ("hate", "/heɪt/", "v.", "恨"),
    ("happy", "/ˈhæpi/", "adj.", "快乐的"),
    ("sad", "/sæd/", "adj.", "悲伤的"),
    ("beautiful", "/ˈbjuːtɪfl/", "adj.", "美丽的"),
    ("ugly", "/ˈʌɡli/", "adj.", "丑陋的"),
    ("big", "/bɪɡ/", "adj.", "大的"),
    ("small", "/smɔːl/", "adj.", "小的"),
    ("fast", "/fɑːst/", "adj.", "快的"),
    ("slow", "/sləʊ/", "adj.", "慢的"),
    ("easy", "/ˈiːzi/", "adj.", "容易的"),
    ("difficult", "/ˈdɪfɪkəlt/", "adj.", "困难的"),
    ("open", "/ˈəʊpən/", "v.", "打开"),
    ("close", "/kləʊz/", "v.", "关闭"),
    ("start", "/stɑːt/", "v.", "开始"),
    ("stop", "/stɒp/", "v.", "停止"),
    ("live", "/lɪv/", "v.", "居住"),
    ("die", "/daɪ/", "v.", "死亡"),
    ("eat", "/iːt/", "v.", "吃"),
    ("drink", "/drɪŋk/", "v.", "喝"),
    ("sleep", "/sliːp/", "v.", "睡觉"),
    ("wake", "/weɪk/", "v.", "醒来"),
    ("walk", "/wɔːk/", "v.", "走"),
    ("drive", "/draɪv/", "v.", "驾驶"),
    ("fly", "/flaɪ/", "v.", "飞"),
    ("swim", "/swɪm/", "v.", "游泳"),
    ("sit", "/sɪt/", "v.", "坐"),
    ("stand", "/stænd/", "v.", "站"),
    ("turn", "/tɜːn/", "v.", "转动"),
    ("move", "/muːv/", "v.", "移动"),
    ("touch", "/tʌtʃ/", "v.", "触摸"),
    ("hold", "/həʊld/", "v.", "握住"),
    ("carry", "/ˈkæri/", "v.", "携带"),
    ("push", "/pʊʃ/", "v.", "推"),
    ("pull", "/pʊl/", "v.", "拉"),
    ("throw", "/θrəʊ/", "v.", "扔"),
    ("catch", "/kætʃ/", "v.", "抓住"),
    ("buy", "/baɪ/", "v.", "买"),
    ("sell", "/sel/", "v.", "卖"),
    ("pay", "/peɪ/", "v.", "支付"),
    ("cost", "/kɒst/", "v.", "花费"),
    ("send", "/send/", "v.", "发送"),
    ("receive", "/rɪˈsiːv/", "v.", "收到"),
    ("show", "/ʃəʊ/", "v.", "展示"),
    ("hide", "/haɪd/", "v.", "隐藏"),
    ("tell", "/tel/", "v.", "告诉"),
    ("ask", "/ɑːsk/", "v.", "问"),
    ("answer", "/ˈɑːnsə/", "v.", "回答"),
    ("help", "/help/", "v.", "帮助"),
    ("wait", "/weɪt/", "v.", "等待"),
    ("follow", "/ˈfɒləʊ/", "v.", "跟随"),
    ("change", "/tʃeɪndʒ/", "v.", "改变"),
    ("break", "/breɪk/", "v.", "打破"),
    ("fix", "/fɪks/", "v.", "修理"),
    ("build", "/bɪld/", "v.", "建造"),
    ("cut", "/kʌt/", "v.", "切"),
    ("mix", "/mɪks/", "v.", "混合"),
    ("wash", "/wɒʃ/", "v.", "洗"),
    ("clean", "/kliːn/", "v.", "清洁"),
    ("cook", "/kʊk/", "v.", "烹饪"),
    ("burn", "/bɜːn/", "v.", "燃烧"),
    ("grow", "/ɡrəʊ/", "v.", "生长"),
    ("plant", "/plɑːnt/", "v.", "种植"),
    ("water", "/ˈwɔːtə/", "n.", "水"),
    ("fire", "/ˈfaɪə/", "n.", "火"),
    ("earth", "/ɜːθ/", "n.", "地球"),
    ("air", "/eə/", "n.", "空气"),
    ("light", "/laɪt/", "n.", "光"),
    ("dark", "/dɑːk/", "n.", "黑暗"),
    ("hot", "/hɒt/", "adj.", "热的"),
    ("cold", "/kəʊld/", "adj.", "冷的"),
    ("warm", "/wɔːm/", "adj.", "温暖的"),
    ("cool", "/kuːl/", "adj.", "凉爽的"),
    ("dry", "/draɪ/", "adj.", "干的"),
    ("wet", "/wet/", "adj.", "湿的"),
    ("hard", "/hɑːd/", "adj.", "硬的"),
    ("soft", "/sɒft/", "adj.", "软的"),
    ("heavy", "/ˈhevi/", "adj.", "重的"),
    ("light", "/laɪt/", "adj.", "轻的"),
    ("sharp", "/ʃɑːp/", "adj.", "锋利的"),
    ("blunt", "/blʌnt/", "adj.", "钝的"),
    ("clean", "/kliːn/", "adj.", "干净的"),
    ("dirty", "/ˈdɜːti/", "adj.", "脏的"),
    ("full", "/fʊl/", "adj.", "满的"),
    ("empty", "/ˈempti/", "adj.", "空的"),
    ("strong", "/strɒŋ/", "adj.", "强壮的"),
    ("weak", "/wiːk/", "adj.", "虚弱的"),
    ("rich", "/rɪtʃ/", "adj.", "富有的"),
    ("poor", "/pɔː/", "adj.", "贫穷的"),
    ("safe", "/seɪf/", "adj.", "安全的"),
    ("dangerous", "/ˈdeɪndʒərəs/", "adj.", "危险的"),
    ("free", "/friː/", "adj.", "自由的"),
    ("busy", "/ˈbɪzi/", "adj.", "忙碌的"),
    ("ready", "/ˈredi/", "adj.", "准备好的"),
    ("sure", "/ʃʊə/", "adj.", "确定的"),
    ("true", "/truː/", "adj.", "真的"),
    ("false", "/fɔːls/", "adj.", "假的"),
    ("real", "/rɪəl/", "adj.", "真实的"),
    ("fake", "/feɪk/", "adj.", "假的"),
    ("correct", "/kəˈrekt/", "adj.", "正确的"),
    ("wrong", "/rɒŋ/", "adj.", "错误的"),
    ("possible", "/ˈpɒsəbl/", "adj.", "可能的"),
    ("impossible", "/ɪmˈpɒsəbl/", "adj.", "不可能的"),
    ("necessary", "/ˈnesəsəri/", "adj.", "必要的"),
    ("enough", "/ɪˈnʌf/", "adj.", "足够的"),
    ("complete", "/kəmˈpliːt/", "adj.", "完整的"),
    ("perfect", "/ˈpɜːfɪkt/", "adj.", "完美的"),
    ("simple", "/ˈsɪmpl/", "adj.", "简单的"),
    ("complex", "/ˈkɒmpleks/", "adj.", "复杂的"),
    ("common", "/ˈkɒmən/", "adj.", "常见的"),
    ("rare", "/reə/", "adj.", "稀有的"),
    ("usual", "/ˈjuːʒuəl/", "adj.", "通常的"),
    ("special", "/ˈspeʃl/", "adj.", "特别的"),
    ("normal", "/ˈnɔːml/", "adj.", "正常的"),
    ("strange", "/streɪndʒ/", "adj.", "奇怪的"),
    ("familiar", "/fəˈmɪliə/", "adj.", "熟悉的"),
    ("foreign", "/ˈfɒrən/", "adj.", "外国的"),
    ("local", "/ˈləʊkl/", "adj.", "本地的"),
    ("national", "/ˈnæʃənl/", "adj.", "国家的"),
    ("international", "/ˌɪntəˈnæʃənl/", "adj.", "国际的"),
    ("social", "/ˈsəʊʃl/", "adj.", "社会的"),
    ("political", "/pəˈlɪtɪkl/", "adj.", "政治的"),
    ("economic", "/ˌiːkəˈnɒmɪk/", "adj.", "经济的"),
    ("cultural", "/ˈkʌltʃərəl/", "adj.", "文化的"),
    ("historical", "/hɪˈstɒrɪkl/", "adj.", "历史的"),
    ("scientific", "/ˌsaɪənˈtɪfɪk/", "adj.", "科学的"),
    ("medical", "/ˈmedɪkl/", "adj.", "医学的"),
    ("educational", "/ˌedʒuˈkeɪʃənl/", "adj.", "教育的"),
    ("technical", "/ˈteknɪkl/", "adj.", "技术的"),
    ("physical", "/ˈfɪzɪkl/", "adj.", "身体的"),
    ("mental", "/ˈmentl/", "adj.", "精神的"),
    ("emotional", "/ɪˈməʊʃənl/", "adj.", "情感的"),
    ("natural", "/ˈnætʃrəl/", "adj.", "自然的"),
    ("artificial", "/ˌɑːtɪˈfɪʃl/", "adj.", "人工的"),
    ("original", "/əˈrɪdʒənl/", "adj.", "原始的"),
    ("modern", "/ˈmɒdn/", "adj.", "现代的"),
    ("traditional", "/trəˈdɪʃənl/", "adj.", "传统的"),
    ("western", "/ˈwestən/", "adj.", "西方的"),
    ("eastern", "/ˈiːstən/", "adj.", "东方的"),
    ("northern", "/ˈnɔːðən/", "adj.", "北方的"),
    ("southern", "/ˈsʌðən/", "adj.", "南方的"),
    ("central", "/ˈsentrəl/", "adj.", "中心的"),
    ("final", "/ˈfaɪnl/", "adj.", "最后的"),
    ("initial", "/ɪˈnɪʃl/", "adj.", "最初的"),
    ("main", "/meɪn/", "adj.", "主要的"),
    ("major", "/ˈmeɪdʒə/", "adj.", "主要的"),
    ("minor", "/ˈmaɪnə/", "adj.", "次要的"),
    ("total", "/ˈtəʊtl/", "adj.", "总计的"),
    ("average", "/ˈævərɪdʒ/", "adj.", "平均的"),
    ("maximum", "/ˈmæksɪməm/", "adj.", "最大的"),
    ("minimum", "/ˈmɪnɪməm/", "adj.", "最小的"),
    ("computer", "/kəmˈpjuːtə/", "n.", "计算机"),
    ("phone", "/fəʊn/", "n.", "电话"),
    ("screen", "/skriːn/", "n.", "屏幕"),
    ("keyboard", "/ˈkiːbɔːd/", "n.", "键盘"),
    ("mouse", "/maʊs/", "n.", "鼠标"),
    ("software", "/ˈsɒftweə/", "n.", "软件"),
    ("hardware", "/ˈhɑːdweə/", "n.", "硬件"),
    ("program", "/ˈprəʊɡræm/", "n.", "程序"),
    ("data", "/ˈdeɪtə/", "n.", "数据"),
    ("file", "/faɪl/", "n.", "文件"),
    ("folder", "/ˈfəʊldə/", "n.", "文件夹"),
    ("network", "/ˈnetwɜːk/", "n.", "网络"),
    ("internet", "/ˈɪntənet/", "n.", "互联网"),
    ("email", "/ˈiːmeɪl/", "n.", "电子邮件"),
    ("website", "/ˈwebsaɪt/", "n.", "网站"),
    ("password", "/ˈpɑːswɜːd/", "n.", "密码"),
    ("account", "/əˈkaʊnt/", "n.", "账户"),
    ("book", "/bʊk/", "n.", "书"),
    ("page", "/peɪdʒ/", "n.", "页"),
    ("chapter", "/ˈtʃæptə/", "n.", "章节"),
    ("story", "/ˈstɔːri/", "n.", "故事"),
    ("word", "/wɜːd/", "n.", "词"),
    ("sentence", "/ˈsentəns/", "n.", "句子"),
    ("paragraph", "/ˈpærəɡrɑːf/", "n.", "段落"),
    ("letter", "/ˈletə/", "n.", "信；字母"),
    ("number", "/ˈnʌmbə/", "n.", "数字"),
    ("question", "/ˈkwestʃən/", "n.", "问题"),
    ("answer", "/ˈɑːnsə/", "n.", "答案"),
    ("example", "/ɪɡˈzɑːmpl/", "n.", "例子"),
    ("reason", "/ˈriːzn/", "n.", "原因"),
    ("result", "/rɪˈzʌlt/", "n.", "结果"),
    ("problem", "/ˈprɒbləm/", "n.", "问题"),
    ("solution", "/səˈluːʃn/", "n.", "解决方案"),
    ("method", "/ˈmeθəd/", "n.", "方法"),
    ("process", "/ˈprəʊses/", "n.", "过程"),
    ("system", "/ˈsɪstəm/", "n.", "系统"),
    ("structure", "/ˈstrʌktʃə/", "n.", "结构"),
    ("level", "/ˈlevl/", "n.", "水平"),
    ("standard", "/ˈstændəd/", "n.", "标准"),
    ("goal", "/ɡəʊl/", "n.", "目标"),
    ("plan", "/plæn/", "n.", "计划"),
    ("idea", "/aɪˈdɪə/", "n.", "想法"),
    ("thought", "/θɔːt/", "n.", "想法"),
    ("memory", "/ˈmeməri/", "n.", "记忆"),
    ("knowledge", "/ˈnɒlɪdʒ/", "n.", "知识"),
    ("skill", "/skɪl/", "n.", "技能"),
    ("ability", "/əˈbɪləti/", "n.", "能力"),
    ("experience", "/ɪkˈspɪəriəns/", "n.", "经验"),
    ("practice", "/ˈpræktɪs/", "n.", "练习"),
    ("study", "/ˈstʌdi/", "n.", "学习"),
    ("research", "/rɪˈsɜːtʃ/", "n.", "研究"),
    ("science", "/ˈsaɪəns/", "n.", "科学"),
    ("mathematics", "/ˌmæθəˈmætɪks/", "n.", "数学"),
    ("language", "/ˈlæŋɡwɪdʒ/", "n.", "语言"),
    ("English", "/ˈɪŋɡlɪʃ/", "n.", "英语"),
    ("Chinese", "/ˌtʃaɪˈniːz/", "n.", "中文"),
    ("history", "/ˈhɪstri/", "n.", "历史"),
    ("geography", "/dʒiˈɒɡrəfi/", "n.", "地理"),
    ("art", "/ɑːt/", "n.", "艺术"),
    ("music", "/ˈmjuːzɪk/", "n.", "音乐"),
    ("sport", "/spɔːt/", "n.", "运动"),
    ("game", "/ɡeɪm/", "n.", "游戏"),
    ("food", "/fuːd/", "n.", "食物"),
    ("fruit", "/fruːt/", "n.", "水果"),
    ("vegetable", "/ˈvedʒtəbl/", "n.", "蔬菜"),
    ("meat", "/miːt/", "n.", "肉"),
    ("fish", "/fɪʃ/", "n.", "鱼"),
    ("rice", "/raɪs/", "n.", "米饭"),
    ("bread", "/bred/", "n.", "面包"),
    ("milk", "/mɪlk/", "n.", "牛奶"),
    ("tea", "/tiː/", "n.", "茶"),
    ("coffee", "/ˈkɒfi/", "n.", "咖啡"),
    ("sugar", "/ˈʃʊɡə/", "n.", "糖"),
    ("salt", "/sɔːlt/", "n.", "盐"),
    ("dog", "/dɒɡ/", "n.", "狗"),
    ("cat", "/kæt/", "n.", "猫"),
    ("bird", "/bɜːd/", "n.", "鸟"),
    ("horse", "/hɔːs/", "n.", "马"),
    ("cow", "/kaʊ/", "n.", "牛"),
    ("pig", "/pɪɡ/", "n.", "猪"),
    ("sheep", "/ʃiːp/", "n.", "羊"),
    ("chicken", "/ˈtʃɪkɪn/", "n.", "鸡"),
    ("duck", "/dʌk/", "n.", "鸭"),
    ("tree", "/triː/", "n.", "树"),
    ("flower", "/ˈflaʊə/", "n.", "花"),
    ("grass", "/ɡrɑːs/", "n.", "草"),
    ("leaf", "/liːf/", "n.", "叶子"),
    ("root", "/ruːt/", "n.", "根"),
    ("seed", "/siːd/", "n.", "种子"),
    ("mountain", "/ˈmaʊntən/", "n.", "山"),
    ("river", "/ˈrɪvə/", "n.", "河"),
    ("lake", "/leɪk/", "n.", "湖"),
    ("sea", "/siː/", "n.", "海"),
    ("forest", "/ˈfɒrɪst/", "n.", "森林"),
    ("desert", "/ˈdezət/", "n.", "沙漠"),
    ("island", "/ˈaɪlənd/", "n.", "岛"),
    ("country", "/ˈkʌntri/", "n.", "国家"),
    ("city", "/ˈsɪti/", "n.", "城市"),
    ("town", "/taʊn/", "n.", "镇"),
    ("village", "/ˈvɪlɪdʒ/", "n.", "村庄"),
    ("road", "/rəʊd/", "n.", "路"),
    ("street", "/striːt/", "n.", "街道"),
    ("bridge", "/brɪdʒ/", "n.", "桥"),
    ("building", "/ˈbɪldɪŋ/", "n.", "建筑物"),
    ("house", "/haʊs/", "n.", "房子"),
    ("room", "/ruːm/", "n.", "房间"),
    ("door", "/dɔː/", "n.", "门"),
    ("window", "/ˈwɪndəʊ/", "n.", "窗户"),
    ("table", "/ˈteɪbl/", "n.", "桌子"),
    ("chair", "/tʃeə/", "n.", "椅子"),
    ("bed", "/bed/", "n.", "床"),
    ("car", "/kɑː/", "n.", "汽车"),
    ("bus", "/bʌs/", "n.", "公交车"),
    ("train", "/treɪn/", "n.", "火车"),
    ("plane", "/pleɪn/", "n.", "飞机"),
    ("ship", "/ʃɪp/", "n.", "船"),
    ("bicycle", "/ˈbaɪsɪkl/", "n.", "自行车"),
    ("money", "/ˈmʌni/", "n.", "钱"),
    ("price", "/praɪs/", "n.", "价格"),
    ("market", "/ˈmɑːkɪt/", "n.", "市场"),
    ("shop", "/ʃɒp/", "n.", "商店"),
    ("factory", "/ˈfæktəri/", "n.", "工厂"),
    ("office", "/ˈɒfɪs/", "n.", "办公室"),
    ("school", "/skuːl/", "n.", "学校"),
    ("hospital", "/ˈhɒspɪtl/", "n.", "医院"),
    ("library", "/ˈlaɪbrəri/", "n.", "图书馆"),
    ("museum", "/mjuˈziːəm/", "n.", "博物馆"),
    ("park", "/pɑːk/", "n.", "公园"),
    ("garden", "/ˈɡɑːdn/", "n.", "花园"),
    ("farm", "/fɑːm/", "n.", "农场"),
    ("family", "/ˈfæməli/", "n.", "家庭"),
    ("father", "/ˈfɑːðə/", "n.", "父亲"),
    ("mother", "/ˈmʌðə/", "n.", "母亲"),
    ("son", "/sʌn/", "n.", "儿子"),
    ("daughter", "/ˈdɔːtə/", "n.", "女儿"),
    ("brother", "/ˈbrʌðə/", "n.", "兄弟"),
    ("sister", "/ˈsɪstə/", "n.", "姐妹"),
    ("friend", "/frend/", "n.", "朋友"),
    ("teacher", "/ˈtiːtʃə/", "n.", "老师"),
    ("student", "/ˈstjuːdnt/", "n.", "学生"),
    ("doctor", "/ˈdɒktə/", "n.", "医生"),
    ("nurse", "/nɜːs/", "n.", "护士"),
    ("farmer", "/ˈfɑːmə/", "n.", "农民"),
    ("worker", "/ˈwɜːkə/", "n.", "工人"),
    ("engineer", "/ˌendʒɪˈnɪə/", "n.", "工程师"),
    ("manager", "/ˈmænɪdʒə/", "n.", "经理"),
    ("leader", "/ˈliːdə/", "n.", "领导者"),
    ("pilot", "/ˈpaɪlət/", "n.", "飞行员"),
    ("soldier", "/ˈsəʊldʒə/", "n.", "士兵"),
    ("artist", "/ˈɑːtɪst/", "n.", "艺术家"),
    ("singer", "/ˈsɪŋə/", "n.", "歌手"),
    ("dancer", "/ˈdɑːnsə/", "n.", "舞者"),
    ("writer", "/ˈraɪtə/", "n.", "作家"),
    ("reader", "/ˈriːdə/", "n.", "读者"),
    ("morning", "/ˈmɔːnɪŋ/", "n.", "早晨"),
    ("afternoon", "/ˌɑːftəˈnuːn/", "n.", "下午"),
    ("evening", "/ˈiːvnɪŋ/", "n.", "晚上"),
    ("night", "/naɪt/", "n.", "夜晚"),
    ("today", "/təˈdeɪ/", "n.", "今天"),
    ("tomorrow", "/təˈmɒrəʊ/", "n.", "明天"),
    ("yesterday", "/ˈjestədeɪ/", "n.", "昨天"),
    ("week", "/wiːk/", "n.", "周"),
    ("month", "/mʌnθ/", "n.", "月"),
    ("season", "/ˈsiːzn/", "n.", "季节"),
    ("spring", "/sprɪŋ/", "n.", "春天"),
    ("summer", "/ˈsʌmə/", "n.", "夏天"),
    ("autumn", "/ˈɔːtəm/", "n.", "秋天"),
    ("winter", "/ˈwɪntə/", "n.", "冬天"),
    ("sun", "/sʌn/", "n.", "太阳"),
    ("moon", "/muːn/", "n.", "月亮"),
    ("star", "/stɑː/", "n.", "星星"),
    ("sky", "/skaɪ/", "n.", "天空"),
    ("cloud", "/klaʊd/", "n.", "云"),
    ("rain", "/reɪn/", "n.", "雨"),
    ("snow", "/snəʊ/", "n.", "雪"),
    ("wind", "/wɪnd/", "n.", "风"),
    ("storm", "/stɔːm/", "n.", "暴风雨"),
    ("head", "/hed/", "n.", "头"),
    ("face", "/feɪs/", "n.", "脸"),
    ("eye", "/aɪ/", "n.", "眼睛"),
    ("ear", "/ɪə/", "n.", "耳朵"),
    ("nose", "/nəʊz/", "n.", "鼻子"),
    ("mouth", "/maʊθ/", "n.", "嘴"),
    ("tooth", "/tuːθ/", "n.", "牙齿"),
    ("hand", "/hænd/", "n.", "手"),
    ("foot", "/fʊt/", "n.", "脚"),
    ("arm", "/ɑːm/", "n.", "手臂"),
    ("leg", "/leɡ/", "n.", "腿"),
    ("heart", "/hɑːt/", "n.", "心"),
    ("brain", "/breɪn/", "n.", "大脑"),
    ("body", "/ˈbɒdi/", "n.", "身体"),
    ("color", "/ˈkʌlə/", "n.", "颜色"),
    ("red", "/red/", "adj.", "红色的"),
    ("blue", "/bluː/", "adj.", "蓝色的"),
    ("green", "/ɡriːn/", "adj.", "绿色的"),
    ("yellow", "/ˈjeləʊ/", "adj.", "黄色的"),
    ("black", "/blæk/", "adj.", "黑色的"),
    ("white", "/waɪt/", "adj.", "白色的"),
    ("orange", "/ˈɒrɪndʒ/", "n.", "橙色；橙子"),
    ("purple", "/ˈpɜːpl/", "adj.", "紫色的"),
    ("pink", "/pɪŋk/", "adj.", "粉色的"),
    ("gray", "/ɡreɪ/", "adj.", "灰色的"),
    ("brown", "/braʊn/", "adj.", "棕色的"),
]


def create_database(csv_path, db_path):
    """Create SQLite database from CSV and common words."""

    # Remove existing database
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Create table
    c.execute("""
        CREATE TABLE dict_words (
            word        TEXT PRIMARY KEY,
            phonetic    TEXT,
            pos         TEXT,
            translation TEXT,
            definition  TEXT,
            exchange    TEXT,
            collins     INTEGER DEFAULT 0,
            oxford      INTEGER DEFAULT 0,
            tag         TEXT,
            bnc         INTEGER,
            frq         INTEGER
        )
    """)

    inserted = set()

    # 1. Insert common words first
    for i, (word, phonetic, pos, translation) in enumerate(COMMON_WORDS):
        if word.lower() in inserted:
            continue
        c.execute(
            "INSERT OR IGNORE INTO dict_words (word, phonetic, pos, translation, bnc, frq) VALUES (?, ?, ?, ?, ?, ?)",
            (word, phonetic, pos, translation, i + 1, i + 1)
        )
        inserted.add(word.lower())

    # Target tags: only import words tagged with these exam labels
    TARGET_TAGS = {'cet4', 'cet6', 'ky', 'ielts', 'toefl', 'gre', 'gk', 'zk'}
    csv_count = 0

    # 2. Insert ECDICT CSV data (filtered by target tags)
    if csv_path and os.path.exists(csv_path):
        try:
            with open(csv_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    word = row.get('word', '').strip()
                    if not word or word.lower() in inserted:
                        continue

                    tag = row.get('tag', '').strip()

                    # Only import words that have at least one target tag
                    if tag:
                        tag_set = set(t.strip() for t in tag.split(' ') if t.strip())
                        if not tag_set & TARGET_TAGS:
                            continue
                    else:
                        # Skip words without any tag
                        continue

                    phonetic = row.get('phonetic', '').strip()
                    pos = row.get('pos', '').strip()
                    translation = row.get('translation', '').strip()
                    definition = row.get('definition', '').strip()
                    exchange = row.get('exchange', '').strip()
                    collins = int(row.get('collins', 0) or 0)
                    oxford = int(row.get('oxford', 0) or 0)
                    bnc = int(row.get('bnc', 0) or 0)
                    frq = int(row.get('frq', 0) or 0)

                    c.execute(
                        """INSERT OR IGNORE INTO dict_words
                        (word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (word, phonetic, pos, translation, definition, exchange,
                         collins, oxford, tag, bnc, frq)
                    )
                    inserted.add(word.lower())
                    csv_count += 1
        except Exception as e:
            print(f"Warning: Error reading CSV: {e}")

    print(f"  - Common words: {len(inserted) - csv_count}")
    print(f"  - CSV tagged words: {csv_count}")

    # 3. Create FTS5 virtual table
    try:
        c.execute("""
            CREATE VIRTUAL TABLE dict_words_fts USING fts5(
                word, exchange,
                content='dict_words', content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2'
            )
        """)

        # Populate FTS
        c.execute("INSERT INTO dict_words_fts(word, exchange) SELECT word, exchange FROM dict_words")
    except Exception as e:
        print(f"Warning: FTS5 creation: {e}")

    # 4. Create indexes
    c.execute("CREATE INDEX IF NOT EXISTS idx_dict_exchange ON dict_words(exchange)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_dict_bnc ON dict_words(bnc)")

    conn.commit()

    # Count
    count = c.execute("SELECT COUNT(*) FROM dict_words").fetchone()[0]
    print(f"Dictionary database created: {count} words")

    conn.close()
    return count


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate ECDICT mini SQLite database')
    parser.add_argument('--input', default='C:/ecdict_mini.csv', help='Input CSV path')
    parser.add_argument('--output', required=True, help='Output database path')
    args = parser.parse_args()

    count = create_database(args.input, args.output)
    print(f"Done! {count} words written to {args.output}")
